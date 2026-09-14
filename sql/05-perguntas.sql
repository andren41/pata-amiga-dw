-- Script 05: As Cinco Perguntas de Negócio
-- Projeto: Data Warehouse Pata Amiga

USE dw_pata_amiga;

-- -----------------------------------------------------------------------------
-- PERGUNTA 1: Onde está o gargalo do processo de entrega?
-- -----------------------------------------------------------------------------
-- Agrupei as médias de tempo por porte de loja. 
-- Um detalhe importante: como deixei as etapas não concluídas como NULL na tabela fato (em vez de zero), 
-- a função AVG ignora essas linhas automaticamente. Se fosse zero, a média seria puxada para baixo de forma errada.
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
-- PERGUNTA 2: Qual categoria concentra o faturamento?
-- -----------------------------------------------------------------------------
-- Aqui o uso da dim_categoria se justifica. Agrupei pelo nome padronizado para 
-- resolver as múltiplas grafias. Para a porcentagem, usei uma subconsulta simples 
-- que traz o faturamento total da rede como denominador.

-- 2.1 Visão geral da rede:
SELECT
    dc.nome_categoria,
    ROUND(SUM(f.vl_liquido), 2) AS faturamento,
    ROUND(100 * SUM(f.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS percentual_do_total
FROM fato_pedido f
JOIN dim_categoria dc ON dc.sk_categoria = f.sk_categoria
GROUP BY dc.nome_categoria
ORDER BY faturamento DESC;

-- 2.2 Visão por porte de loja (para ver se a campeã muda dependendo do tamanho da loja):
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
-- PERGUNTA 3: O desconto funciona igual em todo canal?
-- -----------------------------------------------------------------------------
-- O legal dessa consulta é que não precisa de JOIN. Como padronizei os canais 
-- e a flag de desconto diretamente na tabela fato, tudo se resolve nela mesma.
-- A ideia é analisar o Ticket Médio para ver se a política faz sentido.

-- 3.1 Comparativo do ticket médio com e sem desconto por canal:
SELECT
    canal_pedido,
    houve_desconto,
    COUNT(*) AS pedidos,
    ROUND(AVG(vl_liquido), 2) AS ticket_medio
FROM fato_pedido
GROUP BY canal_pedido, houve_desconto
ORDER BY canal_pedido, houve_desconto;

-- 3.2 Representatividade de cada canal no faturamento total:
SELECT
    canal_pedido,
    ROUND(SUM(vl_liquido), 2) AS faturamento,
    ROUND(100 * SUM(vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS percentual_do_total
FROM fato_pedido
GROUP BY canal_pedido
ORDER BY faturamento DESC;


-- -----------------------------------------------------------------------------
-- PERGUNTA 4: Qual praça de atendimento concentra o faturamento?
-- -----------------------------------------------------------------------------
-- Este é o cruzamento mais complexo do modelo, usando a tabela ponte. 
-- Como uma loja atende várias praças, o JOIN fatalmente duplica o pedido. 
-- Para o faturamento não inflar, multipliquei o valor pelo "fator_publico" de rateio.

-- 4.1 Faturamento rateado por praça:
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

-- 4.2 Prova Real (Auditoria do rateio):
-- Garantindo que a soma rateada + pedidos órfãos batem exatamente com o faturamento da rede.
SELECT
    (SELECT ROUND(SUM(f.vl_liquido * b.fator_publico), 2)
       FROM fato_pedido f
       JOIN dim_loja l ON l.sk_loja = f.sk_loja
       JOIN bridge_loja_praca b ON b.cod_loja = l.cod_loja)  AS soma_rateada,
    (SELECT ROUND(SUM(vl_liquido), 2) FROM fato_pedido WHERE sk_loja = -1) AS sem_loja_identificada,
    (SELECT ROUND(SUM(vl_liquido), 2) FROM fato_pedido)      AS total_da_rede;


-- -----------------------------------------------------------------------------
-- PERGUNTA 5: Onde abrir a próxima loja e as limitações dos dados
-- -----------------------------------------------------------------------------
-- Para ter um dado mais justo, calculei a venda de itens a cada mil habitantes 
-- diretamente na consulta em vez de gravar um número absoluto.

-- 5(a) Ranking por itens a cada 1000 habitantes cruzado com tempo médio de entrega:
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

-- 5(b) O que os dados NÃO permitem afirmar (Faixa de Franquia):
-- A dimensão loja guarda apenas a foto de "hoje" (não criamos histórico/SCD).
-- Portanto, o faturamento abaixo não diz "quanto a loja vendeu enquanto era ouro", 
-- mas sim "quanto faturou a loja que hoje é ouro".
SELECT
    l.faixa_franquia,
    ROUND(SUM(f.vl_liquido), 2) AS faturamento,
    ROUND(100 * SUM(f.vl_liquido) / (SELECT SUM(vl_liquido) FROM fato_pedido), 2) AS percentual_do_total
FROM fato_pedido f
JOIN dim_loja l ON l.sk_loja = f.sk_loja
GROUP BY l.faixa_franquia
ORDER BY faturamento DESC;

-- 5(c) Transparência de Dados: O que ficou de fora da análise?
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