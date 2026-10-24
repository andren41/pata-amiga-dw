-- ============================================================================
-- SCRIPT 04: FACT TABLE TRANSFORMATION & LOAD (`fato_pedido`)
-- Purpose: Sanitize dates, monetary strings, channels, and discounts; resolve
--          dimension surrogate keys (including role-playing dates); and load
--          4,044 order records into `fato_pedido`.
-- ============================================================================

USE dw_pata_amiga;

-- -----------------------------------------------------------------------------
-- FACT TABLE LOAD (fato_pedido)
-- -----------------------------------------------------------------------------
-- Central table of the Data Warehouse. Grain: 1 row per order (4,044 total rows).
-- Consolidates additive metrics, computes delivery stage lead times, and enforces
-- referential integrity by mapping missing Foreign Keys to the -1 default row.
INSERT INTO fato_pedido (
    numero_pedido, sk_tempo_pedido, sk_tempo_entrega, sk_loja, sk_categoria,
    houve_desconto, canal_pedido, dt_pedido, qt_itens, vl_liquido,
    dias_integracao_separacao, dias_separacao_nota, dias_nota_despacho,
    dias_despacho_entrega, dias_total_ate_entrega
)
SELECT
    p.NumeroPedido,

    -- DATE & TIME HANDLING (ROLE-PLAYING DIMENSION)
    -- Raw order timestamps arrive in US format (Month/Day/Year) with AM/PM.
    -- Parsed via STR_TO_DATE using '%m/%d/%Y %h:%i %p' before formatting into the
    -- numeric YYYYMMDD smart key.
    CAST(DATE_FORMAT(STR_TO_DATE(p.DtHoraPedido, '%m/%d/%Y %h:%i %p'), '%Y%m%d') AS SIGNED),

    -- For delivery date, a blank string indicates an order still in transit/open.
    -- In such cases, point the Foreign Key to the -1 control row.
    CASE WHEN p.DtEntregaCliente = '' THEN -1
         ELSE CAST(DATE_FORMAT(DATE(p.DtEntregaCliente), '%Y%m%d') AS SIGNED)
    END,

    -- FOREIGN KEYS (Stores and Categories)
    -- Surrogate keys are resolved via the LEFT JOINs below. If no match is found,
    -- the CASE expression assigns -1 instead of NULL.
    CASE WHEN dl.sk_loja IS NULL THEN -1 ELSE dl.sk_loja END,
    CASE WHEN dc.sk_categoria IS NULL THEN -1 ELSE dc.sk_categoria END,

    -- DEGENERATE DIMENSION STANDARDIZATION IN THE FACT TABLE
    -- Low-cardinality flags cleaned directly during Fact ingestion:
    -- 'HouveDesconto' arrived in 12+ raw variations, normalized into Sim / Nao / Nao Informado.
    CASE WHEN UPPER(TRIM(p.HouveDesconto)) IN ('S','SIM','1','X','TRUE','V') THEN 'Sim'
         WHEN UPPER(TRIM(p.HouveDesconto)) IN ('N','NAO','0','FALSE','F') THEN 'Nao'
         ELSE 'Nao Informado'
    END,

    -- In 'CanalPedido', evaluation order is critical: because 'WhatsApp' contains the
    -- substring 'App', '%WHATS%' must be evaluated and filtered before '%APP%'.
    CASE WHEN UPPER(p.CanalPedido) LIKE '%WHATS%' THEN 'WhatsApp'
         WHEN UPPER(p.CanalPedido) LIKE '%APP%'   THEN 'App'
         WHEN UPPER(p.CanalPedido) LIKE '%SITE%'  THEN 'Site'
         WHEN UPPER(p.CanalPedido) LIKE '%LOJA%'  THEN 'Loja Fisica'
         WHEN UPPER(p.CanalPedido) LIKE '%TEL%'   THEN 'Telefone'
         ELSE 'Nao Informado'
    END,

    -- METRICS & MONETARY VALUES
    STR_TO_DATE(p.DtHoraPedido, '%m/%d/%Y %h:%i %p'),

    -- For numeric quantities, blank strings or hyphens are converted to NULL (never zero).
    CASE WHEN TRIM(p.`QTD.Itens`) IN ('','-') THEN NULL ELSE CAST(p.`QTD.Itens` AS SIGNED) END,

    -- Net revenue (vl_liquido) required multi-format string sanitization: stripping 'R$',
    -- spaces, and thousand separators ('.'), and converting decimal commas (',') to dots
    -- prior to casting as DECIMAL(15,2).
    CASE WHEN TRIM(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$','')) IN ('','-') THEN NULL
         WHEN p.`ValorLiquidoPedido(R$)` LIKE '%,%'
              THEN CAST(REPLACE(REPLACE(REPLACE(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$',''),' ',''),'.',''),',','.')
                    AS DECIMAL(15,2))
         ELSE CAST(REPLACE(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$',''),' ','') AS DECIMAL(15,2))
    END,

    -- LOGISTICS LEAD-TIME INTERVAL CALCULATIONS (Delivery Bottlenecks)
    -- Computed via DATEDIFF between consecutive order milestones.
    -- CRITICAL: If a milestone timestamp is blank, the recorded lag must be NULL.
    -- Recording 0 would artificially pull down average delivery lead times in analytical queries.
    CASE WHEN p.`Dt Separacao Estoque` = '' THEN NULL
         ELSE DATEDIFF(DATE(p.`Dt Separacao Estoque`), DATE(STR_TO_DATE(p.DtHoraIntegracaoERP, '%m/%d/%Y %h:%i %p')))
    END,
    CASE WHEN p.DtNotaFiscal = '' THEN NULL
         ELSE DATEDIFF(DATE(p.DtNotaFiscal), DATE(p.`Dt Separacao Estoque`))
    END,
    CASE WHEN p.Dt_Despacho_Transportadora = '' THEN NULL
         ELSE DATEDIFF(DATE(p.Dt_Despacho_Transportadora), DATE(p.DtNotaFiscal))
    END,
    CASE WHEN p.DtEntregaCliente = '' THEN NULL
         ELSE DATEDIFF(DATE(p.DtEntregaCliente), DATE(p.Dt_Despacho_Transportadora))
    END,
    CASE WHEN p.DtEntregaCliente = '' THEN NULL
         ELSE DATEDIFF(DATE(p.DtEntregaCliente), DATE(STR_TO_DATE(p.DtHoraIntegracaoERP, '%m/%d/%Y %h:%i %p')))
    END

FROM stg_pedido p
-- To resolve the store key, mechanical REPLACE functions first strip the '/SC' suffix and double spaces.
-- Next, a targeted CASE statement resolves 3 specific anomalies (typo, nickname, and abbreviation).
LEFT JOIN dim_loja dl
       ON dl.chave_loja =
          CASE
              WHEN REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ') = 'Pata Amiga Blumenal Centro' THEN 'Pata Amiga Blumenau Centro'
              WHEN REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ') = 'Pata Amiga Floripa Norte'   THEN 'Pata Amiga Florianopolis Norte'
              WHEN REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ') = 'Pata Amiga Jgua do Sul'     THEN 'Pata Amiga Jaragua do Sul'
              ELSE REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ')
          END
-- Category lookup joins directly against the raw source string preserved in dim_categoria.
LEFT JOIN dim_categoria dc
       ON dc.categoria_origem = p.CategoriaProduto;
