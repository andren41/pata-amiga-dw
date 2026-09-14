-- Script 04: Carga da Tabela Fato de Pedidos
-- Projeto: Data Warehouse Pata Amiga

USE dw_pata_amiga;

-- -----------------------------------------------------------------------------
-- CARGA DA FATO_PEDIDO
-- -----------------------------------------------------------------------------
-- Esta é a tabela principal do DW. O grão é de 1 linha por pedido (total de 4.044).
-- O objetivo principal aqui é consolidar as métricas, calcular o tempo das entregas
-- e garantir que nenhuma Foreign Key (FK) fique nula (usando a linha -1 quando necessário).
INSERT INTO fato_pedido (
    numero_pedido, sk_tempo_pedido, sk_tempo_entrega, sk_loja, sk_categoria,
    houve_desconto, canal_pedido, dt_pedido, qt_itens, vl_liquido,
    dias_integracao_separacao, dias_separacao_nota, dias_nota_despacho,
    dias_despacho_entrega, dias_total_ate_entrega
)
SELECT
    p.NumeroPedido,

    -- TRATAMENTO DE TEMPO
    -- A data original do pedido vem no formato americano (Mês/Dia/Ano) com AM/PM.
    -- Precisei usar STR_TO_DATE com a máscara '%m/%d/%Y %h:%i %p' para converter 
    -- corretamente antes de transformar na chave numérica YYYYMMDD.
    CAST(DATE_FORMAT(STR_TO_DATE(p.DtHoraPedido, '%m/%d/%Y %h:%i %p'), '%Y%m%d') AS SIGNED),

    -- Para a data de entrega, se estiver vazio significa que o pedido ainda está em 
    -- andamento. Nesses casos, aponto para a linha de controle -1.
    CASE WHEN p.DtEntregaCliente = '' THEN -1
         ELSE CAST(DATE_FORMAT(DATE(p.DtEntregaCliente), '%Y%m%d') AS SIGNED)
    END,

    -- CHAVES ESTRANGEIRAS (Lojas e Categorias)
    -- As chaves vêm dos LEFT JOINs lá embaixo. Se não houver correspondência, 
    -- o CASE garante que o valor seja -1 em vez de NULL.
    CASE WHEN dl.sk_loja IS NULL THEN -1 ELSE dl.sk_loja END,
    CASE WHEN dc.sk_categoria IS NULL THEN -1 ELSE dc.sk_categoria END,

    -- PADRONIZAÇÃO NA PRÓPRIA FATO
    -- Algumas informações não precisaram virar dimensões, mas precisavam de limpeza.
    -- O 'HouveDesconto' vinha escrito de 17 jeitos diferentes. Resumi tudo em Sim/Não/Não Informado.
    CASE WHEN UPPER(TRIM(p.HouveDesconto)) IN ('S','SIM','1','X','TRUE','V') THEN 'Sim'
         WHEN UPPER(TRIM(p.HouveDesconto)) IN ('N','NAO','0','FALSE','F') THEN 'Nao'
         ELSE 'Nao Informado'
    END,

    -- No 'CanalPedido' a ordem do teste é crítica: como WhatsApp tem 'App' no nome, 
    -- ele precisava ser testado e filtrado primeiro.
    CASE WHEN UPPER(p.CanalPedido) LIKE '%WHATS%' THEN 'WhatsApp'
         WHEN UPPER(p.CanalPedido) LIKE '%APP%'   THEN 'App'
         WHEN UPPER(p.CanalPedido) LIKE '%SITE%'  THEN 'Site'
         WHEN UPPER(p.CanalPedido) LIKE '%LOJA%'  THEN 'Loja Fisica'
         WHEN UPPER(p.CanalPedido) LIKE '%TEL%'   THEN 'Telefone'
         ELSE 'Nao Informado'
    END,

    -- MÉTRICAS E VALORES
    STR_TO_DATE(p.DtHoraPedido, '%m/%d/%Y %h:%i %p'),

    -- Para as métricas numéricas, troquei valores vazios ou hifens por NULL (nunca zero).
    CASE WHEN TRIM(p.`QTD.Itens`) IN ('','-') THEN NULL ELSE CAST(p.`QTD.Itens` AS SIGNED) END,

    -- O valor líquido (faturamento) precisou de uma limpeza bem agressiva, tirando o "R$",
    -- removendo espaços, pontos de milhar e ajustando a vírgula antes de virar DECIMAL.
    CASE WHEN TRIM(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$','')) IN ('','-') THEN NULL
         WHEN p.`ValorLiquidoPedido(R$)` LIKE '%,%'
              THEN CAST(REPLACE(REPLACE(REPLACE(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$',''),' ',''),'.',''),',','.')
                   AS DECIMAL(15,2))
         ELSE CAST(REPLACE(REPLACE(p.`ValorLiquidoPedido(R$)`,'R$',''),' ','') AS DECIMAL(15,2))
    END,

    -- CÁLCULO DE INTERVALOS (Gargalos de Entrega)
    -- Calculei o DATEDIFF entre os marcos do pedido. 
    -- IMPORTANTE: Se um marco está em branco, o tempo gravado tem que ser NULL. 
    -- Se eu colocasse zero, iria distorcer a média de entrega para baixo nas análises.
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
-- Para encontrar a loja correta, primeiro limpei o sufixo '/SC' e espaços duplos.
-- Depois, um CASE trata manualmente 3 erros específicos (digitação, apelido e abreviação).
LEFT JOIN dim_loja dl
       ON dl.chave_loja =
          CASE
              WHEN REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ') = 'Pata Amiga Blumenal Centro' THEN 'Pata Amiga Blumenau Centro'
              WHEN REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ') = 'Pata Amiga Floripa Norte'   THEN 'Pata Amiga Florianopolis Norte'
              WHEN REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ') = 'Pata Amiga Jgua do Sul'     THEN 'Pata Amiga Jaragua do Sul'
              ELSE REPLACE(REPLACE(TRIM(p.`Loja-Nome`), '/SC', ''), '  ', ' ')
          END
-- O JOIN da categoria é bem mais direto, conectando direto na chave crua da dimensão.
LEFT JOIN dim_categoria dc
       ON dc.categoria_origem = p.CategoriaProduto;