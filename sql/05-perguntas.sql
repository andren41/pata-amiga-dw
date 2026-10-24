-- ============================================================================
-- SCRIPT 05: EXECUTIVE BUSINESS QUERIES (Q1 TO Q5)
-- Purpose: Answer the 5 core analytical questions on delivery bottlenecks,
--          category revenue, channel discounts, regional proration, and
--          store expansion using the Star Schema Data Warehouse.
-- ============================================================================

USE dw_pata_amiga;

-- -----------------------------------------------------------------------------
-- QUESTION 1: Where is the bottleneck in the delivery process?
-- -----------------------------------------------------------------------------
-- Grouped average lead times by store size (porte).
-- Important detail: because uncompleted stages were stored as NULL in the fact
-- table (instead of zero), the AVG() function automatically ignores those rows.
-- If zeros had been used, the averages would be artificially skewed downward.
SELECT
    l.porte,
    COUNT(*) AS pedidos,
    ROUND(AVG(f.dias_integracao_separacao), 1) AS media_integracao_separacao,
    ROUND(AVG(f.dias_separacao_nota), 1)       AS media_separacao_nota,
    ROUND(AVG(f.dias_nota_despacho), 1)        AS media_nota_despacho,
    ROUND(AVG(f.dias_despacho_entrega), 1)     AS media_despacho_entrega,
    ROUND(AVG(f.dias_total_ate_entrega), 1)    AS media_total_ate_entrega
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
GROUP BY l.porte
ORDER BY l.porte;


-- -----------------------------------------------------------------------------
-- QUESTION 2: Which category concentrates total revenue?
-- -----------------------------------------------------------------------------
-- This query justifies the dedicated dim_categoria table: grouping by the
-- standardized category name resolves the 18 raw spelling variations.
-- For the percentage share, a scalar subquery retrieves total chain revenue
-- as the denominator.

-- 2.1 Chain-wide overview:
SELECT
    dc.nome_categoria,
    ROUND(SUM(f.vl_liquido), 2) AS faturamento,
    ROUND(100 * SUM(f.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS percentual_do_total
FROM fato_pedido f
JOIN dim_categoria dc ON dc.sk_categoria = f.sk_categoria
GROUP BY dc.nome_categoria
ORDER BY faturamento DESC;

-- 2.2 Breakdown by store size (to check whether the top category changes by store format):
SELECT
    l.porte,
    dc.nome_categoria,
    ROUND(SUM(f.vl_liquido), 2) AS faturamento
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
JOIN dim_categoria dc ON dc.sk_categoria = f.sk_categoria
GROUP BY l.porte, dc.nome_categoria
ORDER BY l.porte, faturamento DESC;


-- -----------------------------------------------------------------------------
-- QUESTION 3: Does the discount policy perform equally across all channels?
-- -----------------------------------------------------------------------------
-- A key advantage of this query is that no JOIN is required. Since order channels
-- and the discount flag were standardized directly in the fact table (degenerate
-- dimensions), everything is resolved within fato_pedido itself.
-- The goal is to evaluate Average Ticket (Ticket Médio) to assess policy consistency.

-- 3.1 Average ticket comparison with vs. without discount by channel:
SELECT
    canal_pedido,
    houve_desconto,
    COUNT(*) AS pedidos,
    ROUND(AVG(vl_liquido), 2) AS ticket_medio
FROM fato_pedido
GROUP BY canal_pedido, houve_desconto
ORDER BY canal_pedido, houve_desconto;

-- 3.2 Revenue share of each sales channel across total chain revenue:
SELECT
    canal_pedido,
    ROUND(SUM(vl_liquido), 2) AS faturamento,
    ROUND(100 * SUM(vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS percentual_do_total
FROM fato_pedido
GROUP BY canal_pedido
ORDER BY faturamento DESC;


-- -----------------------------------------------------------------------------
-- QUESTION 4: Which service region (praça) concentrates revenue?
-- -----------------------------------------------------------------------------
-- This is the most complex join in the model, leveraging the N:N bridge table.
-- Because a single store can serve multiple service regions, the JOIN inevitably
-- duplicates (fans out) order rows. To prevent revenue inflation, order revenue
-- is multiplied by the "fator_publico" proration weight.

-- 4.1 Prorated revenue by service region:
SELECT
    dp.nome_praca,
    dp.domicilios_com_pet,
    ROUND(SUM(f.vl_liquido * b.fator_publico), 2) AS faturamento_rateado
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
JOIN bridge_loja_praca b ON b.cod_loja = l.cod_loja
JOIN dim_praca dp ON dp.sk_praca = b.sk_praca
GROUP BY dp.nome_praca, dp.domicilios_com_pet
ORDER BY faturamento_rateado DESC;

-- 4.2 Reconciliation Audit (Proration Proof):
-- Verifying that prorated revenue + unidentified store orders match total chain revenue exactly.
SELECT
    (SELECT ROUND(SUM(f.vl_liquido * b.fator_publico), 2)
       FROM fato_pedido f
       JOIN dim_loja l ON l.sk_loja = f.sk_loja
       JOIN bridge_loja_praca b ON b.cod_loja = l.cod_loja)  AS soma_rateada,
    (SELECT ROUND(SUM(vl_liquido), 2) FROM fato_pedido WHERE sk_loja = -1) AS sem_loja_identificada,
    (SELECT ROUND(SUM(vl_liquido), 2) FROM fato_pedido)      AS total_da_rede;


-- -----------------------------------------------------------------------------
-- QUESTION 5: Where to open the next store & data limitations
-- -----------------------------------------------------------------------------
-- For a fairer comparison across municipalities of different sizes, items sold
-- per 1,000 inhabitants are calculated dynamically in the query rather than
-- relying on raw absolute volume.

-- 5(a) Store ranking by items sold per 1,000 inhabitants cross-referenced with average delivery lead time:
SELECT
    l.nome_loja,
    l.populacao_cidade,
    SUM(f.qt_itens) AS itens_vendidos,
    ROUND(SUM(f.qt_itens) / (l.populacao_cidade / 1000), 2) AS itens_por_mil_habitantes,
    ROUND(AVG(f.dias_total_ate_entrega), 1) AS tempo_medio_entrega_dias
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
WHERE l.sk_loja <> -1
GROUP BY l.sk_loja, l.nome_loja, l.populacao_cidade
ORDER BY itens_por_mil_habitantes DESC;

-- 5(b) What the data CANNOT claim (Franchise Tier / SCD Limitation):
-- The store dimension only stores the current snapshot (no historical tracking / SCD Type 2).
-- Therefore, the revenue below does not state "how much a store sold while in the Gold tier",
-- but rather "total revenue generated by stores that are currently classified as Gold today".
SELECT
    l.faixa_franquia,
    ROUND(SUM(f.vl_liquido), 2) AS faturamento,
    ROUND(100 * SUM(f.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS percentual_do_total
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
GROUP BY l.faixa_franquia
ORDER BY faturamento DESC;

-- 5(c) Data Transparency Audit: What was left out or incomplete in the analysis?
SELECT 'pedidos sem loja identificada' AS o_que_ficou_de_fora, COUNT(*) AS quantidade
FROM fato_pedido WHERE sk_loja = -1
UNION ALL
SELECT 'entregas ainda nao concluidas', COUNT(*)
FROM fato_pedido WHERE sk_tempo_entrega = -1
UNION ALL
SELECT 'pedidos com itens em branco', COUNT(*)
FROM fato_pedido WHERE qt_itens IS NULL
UNION ALL
SELECT 'pedidos com valor em branco', COUNT(*)
FROM fato_pedido WHERE vl_liquido IS NULL;
