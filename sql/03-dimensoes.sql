-- Script 03: Preenchimento das Dimensões (Categoria e Praça) e da Tabela Ponte
-- Projeto: Data Warehouse Pata Amiga

USE dw_pata_amiga;

-- -----------------------------------------------------------------------------
-- 1. DIMENSÃO CATEGORIA
-- -----------------------------------------------------------------------------
-- Inserindo primeiro a linha de controle (-1) para evitar chaves nulas na fato.
INSERT INTO dim_categoria (sk_categoria, categoria_origem, nome_categoria, grupo_categoria)
VALUES (-1, 'Nao Informado', 'Nao Informado', 'Nao Informado');

-- Aqui faço o de-para das grafias. Decidi manter a categoria_origem crua para facilitar 
-- o JOIN com a staging depois. 
-- Detalhe importante na lógica: a ordem do CASE importa muito. Coloquei 'MED' antes 
-- de 'RA' para garantir que a 'Ração Medicamentosa' vá para Medicamento e não para Ração.
INSERT INTO dim_categoria (categoria_origem, nome_categoria, grupo_categoria)
SELECT DISTINCT
    `CategoriaProduto`,
    CASE
        WHEN UPPER(`CategoriaProduto`) LIKE '%MED%'    THEN 'Medicamento'
        WHEN UPPER(`CategoriaProduto`) LIKE '%PETISC%' THEN 'Petisco'
        WHEN UPPER(`CategoriaProduto`) LIKE '%RA%'     THEN 'Racao'
        WHEN UPPER(`CategoriaProduto`) LIKE '%HIG%'    THEN 'Higiene'
        WHEN UPPER(`CategoriaProduto`) LIKE '%BRINQ%'  THEN 'Brinquedo'
        WHEN UPPER(`CategoriaProduto`) LIKE '%ACESS%'  THEN 'Acessorio'
        WHEN UPPER(`CategoriaProduto`) LIKE '%SERV%'   THEN 'Servico'
        ELSE 'Nao Informado'
    END,
    CASE
        WHEN UPPER(`CategoriaProduto`) LIKE '%MED%'    THEN 'Saude e Higiene'
        WHEN UPPER(`CategoriaProduto`) LIKE '%PETISC%' THEN 'Alimentacao'
        WHEN UPPER(`CategoriaProduto`) LIKE '%RA%'     THEN 'Alimentacao'
        WHEN UPPER(`CategoriaProduto`) LIKE '%HIG%'    THEN 'Saude e Higiene'
        WHEN UPPER(`CategoriaProduto`) LIKE '%BRINQ%'  THEN 'Bem-estar'
        WHEN UPPER(`CategoriaProduto`) LIKE '%ACESS%'  THEN 'Bem-estar'
        WHEN UPPER(`CategoriaProduto`) LIKE '%SERV%'   THEN 'Bem-estar'
        ELSE 'Nao Informado'
    END
FROM stg_pedido;


-- -----------------------------------------------------------------------------
-- 2. DIMENSÃO PRAÇA
-- -----------------------------------------------------------------------------
-- Inserindo a linha -1 padrão.
INSERT INTO dim_praca (sk_praca, cod_praca, nome_praca, regional, domicilios_com_pet)
VALUES (-1, 'N/I', 'Nao Informado', 'Nao Informado', NULL);

-- A origem traz as praças repetidas por loja, então usei GROUP BY no CodPraca
-- para colapsar e ter uma linha única por praça. 
-- Também limpei o ponto de milhar da coluna de domicílios antes de converter pra número.
INSERT INTO dim_praca (cod_praca, nome_praca, regional, domicilios_com_pet)
SELECT
    CodPraca,
    MAX(NomePraca),
    MAX(Regional),
    CAST(REPLACE(MAX(DomiciliosComPet), '.', '') AS SIGNED)
FROM stg_loja_praca
GROUP BY CodPraca;


-- -----------------------------------------------------------------------------
-- 3. BRIDGE LOJA -> PRAÇA (Tabela Ponte)
-- -----------------------------------------------------------------------------
-- Como a relação entre Loja e Praça é N:N, precisei dessa tabela intermediária.
-- Ela guarda o fator de rateio do público para o faturamento não duplicar depois.
-- A ligação com a loja é feita pela chave natural (CodLoja).
INSERT INTO bridge_loja_praca (cod_loja, sk_praca, fator_publico)
SELECT
    slp.CodLoja,
    dp.sk_praca,
    CAST(slp.PercentualPublico AS DECIMAL(6,4))
FROM stg_loja_praca slp
JOIN dim_praca dp ON dp.cod_praca = slp.CodPraca;