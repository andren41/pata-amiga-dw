-- ============================================================================
-- SCRIPT 03: DIMENSION & BRIDGE TABLES POPULATION
-- Purpose: Clean, standardize, and populate `dim_categoria`, `dim_praca`,
--          and the N:N proration bridge table `bridge_loja_praca`.
-- ============================================================================

USE dw_pata_amiga;

-- -----------------------------------------------------------------------------
-- 1. CATEGORY DIMENSION (dim_categoria)
-- -----------------------------------------------------------------------------
-- Insert the default unknown member row (-1) first to prevent NULL FKs in the Fact table.
INSERT INTO dim_categoria (sk_categoria, categoria_origem, nome_categoria, grupo_categoria)
VALUES (-1, 'Nao Informado', 'Nao Informado', 'Nao Informado');

-- Map the 18 raw spelling variations into 7 canonical categories.
-- Preserving `categoria_origem` as the raw string simplifies the staging-to-dimension JOIN later.
-- Critical logic detail: CASE evaluation order matters. 'MED' is evaluated before 'RA'
-- so that 'Ração Medicamentosa' (Medicated Pet Food) is classified under Medication ('Medicamento')
-- rather than standard Pet Food ('Racao').
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
-- 2. SERVICE REGION DIMENSION (dim_praca)
-- -----------------------------------------------------------------------------
-- Insert the standard -1 default row.
INSERT INTO dim_praca (sk_praca, cod_praca, nome_praca, regional, domicilios_com_pet)
VALUES (-1, 'N/I', 'Nao Informado', 'Nao Informado', NULL);

-- Because the staging table repeats service regions across stores, GROUP BY on CodPraca
-- collapses the records into a single unique row per region.
-- The thousand separator ('.') in DomiciliosComPet is stripped prior to integer casting.
INSERT INTO dim_praca (cod_praca, nome_praca, regional, domicilios_com_pet)
SELECT
    CodPraca,
    MAX(NomePraca),
    MAX(Regional),
    CAST(REPLACE(MAX(DomiciliosComPet), '.', '') AS SIGNED)
FROM stg_loja_praca
GROUP BY CodPraca;


-- -----------------------------------------------------------------------------
-- 3. STORE -> SERVICE REGION BRIDGE TABLE (bridge_loja_praca)
-- -----------------------------------------------------------------------------
-- Resolves the N:N relationship between Stores and Service Regions.
-- Stores the audience proration weight (fator_publico) to prevent revenue duplication during joins.
-- Links to the store via its natural business key (CodLoja).
INSERT INTO bridge_loja_praca (cod_loja, sk_praca, fator_publico)
SELECT
    slp.CodLoja,
    dp.sk_praca,
    CAST(slp.PercentualPublico AS DECIMAL(6,4))
FROM stg_loja_praca slp
JOIN dim_praca dp ON dp.cod_praca = slp.CodPraca;
