-- ============================================================================
-- SCRIPT 00: DATA QUALITY & STAGING DIAGNOSTICS (UNIT TESTS)
-- Purpose: Audit raw data imported from the 3 source systems (E-commerce,
--          Store Registry, and Service Regions) and validate row counts,
--          referential integrity, and business rules across every ETL stage.
-- ============================================================================

USE dw_pata_amiga;

-- =====================================================================================
--  AFTER SCRIPT 01 - STAGING LAYER VALIDATION
-- =====================================================================================
SELECT 'stg_pedido'     AS tabela, COUNT(*) AS linhas, 4044 AS esperado FROM stg_pedido
UNION ALL SELECT 'stg_loja',       COUNT(*), 32 FROM stg_loja
UNION ALL SELECT 'stg_loja_praca', COUNT(*), 48 FROM stg_loja_praca;

-- Initial Staging Diagnostics (metrics documented in the README).
SELECT 'grafias distintas de categoria (no MySQL)' AS diagnostico,
       COUNT(DISTINCT `CategoriaProduto`) AS valor, '18' AS esperado FROM stg_pedido
UNION ALL SELECT 'grafias distintas de nome de loja',
       COUNT(DISTINCT `Loja-Nome`), '(conte e descreva)' FROM stg_pedido
UNION ALL SELECT 'grafias distintas de HouveDesconto',
       COUNT(DISTINCT `HouveDesconto`), '(conte)' FROM stg_pedido
UNION ALL SELECT 'grafias distintas de CanalPedido',
       COUNT(DISTINCT `CanalPedido`), '(conte)' FROM stg_pedido
UNION ALL SELECT 'pedidos sem Cod Loja preenchido',
       SUM(CASE WHEN `Cod Loja` = '' THEN 1 ELSE 0 END), '1575  (~39%)' FROM stg_pedido
UNION ALL SELECT 'pedidos sem nome de loja (vao para a -1)',
       SUM(CASE WHEN `Loja-Nome` = '' THEN 1 ELSE 0 END), '3' FROM stg_pedido;

-- Blank logistics milestones = open/in-progress orders. Will be stored as NULL lead-time days.
SELECT 'Dt Separacao Estoque' AS marco,
       SUM(CASE WHEN `Dt Separacao Estoque` = '' THEN 1 ELSE 0 END) AS em_branco,
       1077 AS esperado FROM stg_pedido
UNION ALL SELECT 'DtNotaFiscal',
       SUM(CASE WHEN `DtNotaFiscal` = '' THEN 1 ELSE 0 END), 1338 FROM stg_pedido
UNION ALL SELECT 'Dt_Despacho_Transportadora',
       SUM(CASE WHEN `Dt_Despacho_Transportadora` = '' THEN 1 ELSE 0 END), 1665 FROM stg_pedido
UNION ALL SELECT 'DtEntregaCliente',
       SUM(CASE WHEN `DtEntregaCliente` = '' THEN 1 ELSE 0 END), 1953 FROM stg_pedido;

-- Date mask comparison. Run prior to loading the Fact table.
-- The first column must return 4044 and the second must return 0.
-- If inverted, the chosen date parsing mask is incorrect.
SELECT
    SUM(CASE WHEN STR_TO_DATE(`DtHoraPedido`, '%m/%d/%Y %h:%i %p') IS NOT NULL
             THEN 1 ELSE 0 END) AS mascara_AMERICANA_ok,
    SUM(CASE WHEN STR_TO_DATE(`DtHoraPedido`, '%d/%m/%Y %h:%i %p') IS NOT NULL
             THEN 1 ELSE 0 END) AS mascara_BRASILEIRA_ok
FROM stg_pedido;

-- =====================================================================================
--  AFTER SCRIPT 02 - STATIC DIMENSIONS & EMPTY DDL SKELETON
-- =====================================================================================
SELECT 'dim_tempo' AS tabela, COUNT(*) AS linhas, '236  (235 dias + a -1)' AS esperado
FROM dim_tempo
UNION ALL SELECT 'dim_loja', COUNT(*), '33  (32 lojas + a -1)' FROM dim_loja;

-- The four target tables below are created empty. All counts must equal zero at this stage.
SELECT 'dim_categoria' AS tabela, COUNT(*) AS deve_estar_vazia FROM dim_categoria
UNION ALL SELECT 'dim_praca',         COUNT(*) FROM dim_praca
UNION ALL SELECT 'bridge_loja_praca', COUNT(*) FROM bridge_loja_praca
UNION ALL SELECT 'fato_pedido',       COUNT(*) FROM fato_pedido;

-- =====================================================================================
--  AFTER SCRIPT 03 - POPULATED DIMENSIONS & BRIDGE TABLE
-- =====================================================================================
SELECT 'dim_categoria'     AS tabela, COUNT(*) AS linhas,
       '19 no MySQL - varia por banco' AS esperado FROM dim_categoria
UNION ALL SELECT 'dim_praca',         COUNT(*), '13  (12 pracas + a -1)' FROM dim_praca
UNION ALL SELECT 'bridge_loja_praca', COUNT(*), '48' FROM bridge_loja_praca;

-- Core standardization check: must return 8 (7 canonical categories + row -1) across any RDBMS.
SELECT COUNT(DISTINCT nome_categoria) AS categorias_padronizadas,
       '8 = as 7 categorias + a linha -1' AS esperado FROM dim_categoria;

-- If 'Nao Informado' appears in any row other than sk_categoria = -1, a CASE WHEN branch
-- failed to classify a spelling variation. This query must return EMPTY.
SELECT categoria_origem, nome_categoria FROM dim_categoria
WHERE nome_categoria = 'Nao Informado' AND sk_categoria <> -1;

-- CASE evaluation order test 1: "Racao Medicamentosa" must map to 'Medicamento'.
-- If 'Racao' appears in the second column, the CASE statement evaluated RA before MED.
SELECT categoria_origem, nome_categoria, 'Medicamento' AS esperado
FROM dim_categoria WHERE UPPER(categoria_origem) LIKE '%MEDICAMENTOSA%';


-- Bridge table check: audience weights must sum to 1.0000 per store. Query must return EMPTY.
SELECT cod_loja, ROUND(SUM(fator_publico), 4) AS soma_dos_fatores
FROM bridge_loja_praca GROUP BY cod_loja
HAVING ROUND(SUM(fator_publico), 4) <> 1;

-- All 32 stores must exist in the bridge table, and every region must be linked to at least one store.
SELECT 'lojas na ponte' AS teste, COUNT(DISTINCT cod_loja) AS valor, '32' AS esperado
FROM bridge_loja_praca
UNION ALL SELECT 'pracas na ponte', COUNT(DISTINCT sk_praca), '12' FROM bridge_loja_praca;

-- Every dimension requires the default -1 unknown member row. Both must return 1 here.
SELECT 'dim_categoria' AS dimensao, COUNT(*) AS tem_a_linha_menos_1
FROM dim_categoria WHERE sk_categoria = -1
UNION ALL SELECT 'dim_praca',       COUNT(*) FROM dim_praca       WHERE sk_praca = -1;

-- =====================================================================================
--  AFTER SCRIPT 04 - FACT TABLE VALIDATION
-- =====================================================================================
SELECT COUNT(*) AS linhas, '4044' AS esperado FROM fato_pedido;
-- > 4,044 indicates a JOIN is duplicating rows; < 4,044 indicates a JOIN is dropping rows.

-- No Foreign Key can be NULL, and no Foreign Key can be an orphan (pointing to a missing PK).
SELECT 'FK nula' AS teste, COUNT(*) AS deve_ser_zero FROM fato_pedido
WHERE sk_loja IS NULL OR sk_categoria IS NULL
   OR sk_tempo_pedido IS NULL OR sk_tempo_entrega IS NULL
UNION ALL SELECT 'FK orfa (loja)', COUNT(*)
FROM fato_pedido f LEFT JOIN dim_loja d ON d.sk_loja = f.sk_loja
WHERE d.sk_loja IS NULL
UNION ALL SELECT 'FK orfa (categoria)', COUNT(*)
FROM fato_pedido f LEFT JOIN dim_categoria d ON d.sk_categoria = f.sk_categoria
WHERE d.sk_categoria IS NULL
UNION ALL SELECT 'FK orfa (tempo da entrega)', COUNT(*)
FROM fato_pedido f LEFT JOIN dim_tempo d ON d.sk_tempo = f.sk_tempo_entrega
WHERE d.sk_tempo IS NULL;

-- Expected non-zero counts mapped to the -1 unknown member row:
SELECT 'pedidos sem loja (na linha -1)' AS informativo, COUNT(*) AS valor,
       '3' AS esperado FROM fato_pedido WHERE sk_loja = -1
UNION ALL SELECT 'entregas ainda nao feitas (tempo na -1)', COUNT(*), '1953'
FROM fato_pedido WHERE sk_tempo_entrega = -1;

-- Channel CASE evaluation order test (Script 04): 'WhatsApp' must appear in the Fact table.
-- If this query returns EMPTY, the CASE evaluated APP before WHATS and absorbed WhatsApp into App.
SELECT canal_pedido, COUNT(*) AS pedidos FROM fato_pedido
WHERE canal_pedido = 'WhatsApp' GROUP BY canal_pedido;

-- Order date range check: must span 2023-09-01 to 2024-03-31.
-- Min or Max dates outside this window indicate an incorrect date parsing mask.
SELECT MIN(DATE(dt_pedido)) AS primeiro_pedido, MAX(DATE(dt_pedido)) AS ultimo_pedido,
       '2023-09-01 a 2024-03-31' AS esperado FROM fato_pedido;

-- Lead-time days can never be negative, as the logistics workflow is sequential.
SELECT 'dias negativos' AS teste, COUNT(*) AS deve_ser_zero FROM fato_pedido
WHERE dias_integracao_separacao < 0 OR dias_separacao_nota < 0
   OR dias_nota_despacho < 0 OR dias_despacho_entrega < 0
   OR dias_total_ate_entrega < 0;

-- =====================================================================================
--  AFTER SCRIPT 05 - BUSINESS QUERIES RECONCILIATION
-- =====================================================================================
-- Verify that category revenue sum matches total Fact revenue. A mismatch indicates dropped rows in JOIN.
SELECT
    (SELECT ROUND(SUM(vl_liquido)) FROM fato_pedido)             AS total_na_fato,
    (SELECT ROUND(SUM(f.vl_liquido)) FROM fato_pedido f
       JOIN dim_categoria c ON c.sk_categoria = f.sk_categoria)  AS total_pela_P2;
-- Both columns must return the exact same value.

-- Q4 Proration Audit: prorated regional sum + unidentified store orders must equal total chain revenue.
-- The last column must equal ZERO.
-- The difference is rounded ONCE at the end (rather than rounding each sum separately)
-- to avoid 1 or 2 BRL rounding residuals on an exact match.
SELECT
    (SELECT ROUND(SUM(vl_liquido)) FROM fato_pedido) AS total_da_rede,
    (SELECT ROUND(SUM(f.vl_liquido * b.fator_publico))
       FROM fato_pedido f
       JOIN dim_loja l ON l.sk_loja = f.sk_loja
       JOIN bridge_loja_praca b ON b.cod_loja = l.cod_loja) AS soma_rateada,
    (SELECT ROUND(SUM(vl_liquido)) FROM fato_pedido WHERE sk_loja = -1) AS sem_loja,
    ROUND(
        (SELECT SUM(vl_liquido) FROM fato_pedido)
        - (SELECT SUM(f.vl_liquido * b.fator_publico)
             FROM fato_pedido f
             JOIN dim_loja l ON l.sk_loja = f.sk_loja
             JOIN bridge_loja_praca b ON b.cod_loja = l.cod_loja)
        - (SELECT SUM(vl_liquido) FROM fato_pedido WHERE sk_loja = -1)
    )                                                    AS tem_de_dar_ZERO;
