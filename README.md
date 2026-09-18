\# Pata Amiga — Análise de Dados (Mini-Projeto, Módulo 2 · Semana 7)



Modelo dimensional e análise dos 4.044 pedidos da Pata Amiga (rede de pet shops de Santa Catarina) entre setembro/2023 e março/2024, construído a partir de três bases de origem desnormalizadas (e-commerce, cadastro de lojas e praças de atendimento).



\## Sumário

1\. \[Contextualização](#1-contextualização)

2\. \[Diagnóstico da origem](#2-diagnóstico-da-origem-tarefa-1)

3\. \[Modelo dimensional](#3-modelo-dimensional)

4\. \[Decisões de tratamento](#4-decisões-de-tratamento)

5\. \[Como reproduzir o banco do zero](#5-como-reproduzir-o-banco-do-zero)

6\. \[As cinco respostas](#6-as-cinco-respostas)

7\. \[Recomendação final](#7-recomendação-final)

8\. \[Vídeo](#8-vídeo)



\---



\## 1. Contextualização

A Pata Amiga é uma rede catarinense de pet shops com 32 lojas. Em setembro de 2023, a rede unificou a operação de pedidos (app, site, telefone, WhatsApp e loja física) com a entrega, gerando 4.044 pedidos em sete meses. 



Esses dados nasceram em três sistemas que não se falam — a plataforma de e-commerce, o cadastro de lojas do franchising e a planilha de praças de atendimento do time de expansão — cada um com sua própria bagunça de formatação. Este projeto organiza essas três origens num modelo dimensional (esquema estrela) e responde cinco perguntas de negócio da diretoria: onde está o gargalo da entrega, qual categoria sustenta o faturamento, se a política de desconto é consistente entre canais, onde está concentrado o faturamento por praça, e onde abrir a próxima loja.



\---



\## 2. Diagnóstico da origem (Tarefa 1)

Levantado a partir das três tabelas de staging (`stg\_pedido`, `stg\_loja`, `stg\_loja\_praca`), antes de qualquer tratamento:



| Item | Valor |

|---|---|

| \*\*Linhas em stg\_pedido / stg\_loja / stg\_loja\_praca\*\* | 4.044 / 32 / 48 |

| \*\*Grafias distintas de nome de loja\*\* | 50 |

| \*\*Grafias distintas de categoria de produto\*\* | 18 |

| \*\*Grafias distintas de "Houve Desconto"\*\* | 12 |

| \*\*Grafias distintas de canal do pedido\*\* | 8 |

| \*\*Pedidos sem Cod Loja preenchido\*\* | 1.575 (\~39%) |

| \*\*Pedidos sem Loja-Nome preenchido\*\* (loja não identificável) | 3 |

| \*\*Marco "Separação" em branco\*\* | 1.077 |

| \*\*Marco "Nota Fiscal" em branco\*\* | 1.338 |

| \*\*Marco "Despacho" em branco\*\* | 1.665 |

| \*\*Marco "Entrega" em branco\*\* | 1.953 |



> \*\*Nota importante:\*\* Os 1.575 pedidos sem `Cod Loja` não significam 1.575 lojas não identificadas — o modelo resolve a loja pelo nome (`Loja-Nome`), não pelo código, e o nome está presente na grande maioria desses casos. Só 3 pedidos ficam de fato sem loja identificável (nome também vazio), e são esses 3 que caem na linha -1 da dimensão. Os marcos em branco não são erro de carga: representam processos ainda em aberto (a janela de dados termina antes de o pedido concluir todas as etapas).



\---



\## 3. Modelo dimensional



!\[Modelo Dimensional](diagrama/modelo-estrela.png)



\* Uma fato (`fato\_pedido`, grão = 1 linha por pedido) e quatro dimensões: `dim\_tempo`, `dim\_loja`, `dim\_categoria` ligadas diretamente à fato, e `dim\_praca` ligada indiretamente através da tabela ponte `bridge\_loja\_praca` (única ligação N:N do modelo, pois uma loja atende mais de uma praça).

\* `dim\_tempo` é usada duas vezes na fato — como role-playing dimension — para representar a data do pedido (`sk\_tempo\_pedido`) e a data da entrega (`sk\_tempo\_entrega`) com a mesma tabela de calendário.

\* Toda dimensão tem uma linha `-1` = "Não Informado", garantindo que nenhuma FK na fato fique nula mesmo quando o dado de origem falta.



\---



\## 4. Decisões de tratamento



\* \*\*Datas:\*\* A data do pedido vem no formato americano com AM/PM (`11/16/2023 02:30 PM`), convertida com `STR\_TO\_DATE(coluna, '%m/%d/%Y %h:%i %p')`. Os quatro marcos da entrega já vêm em ISO (`2023-11-16`), bastando `DATE()`. Usar a máscara brasileira não gera erro, mas devolve NULL ou datas trocadas em silêncio — por isso a máscara certa foi conferida antes (as 4.044 datas batem com a máscara americana).

\* \*\*Valores em dinheiro e quantidades:\*\* Vazio ou `-` vira `NULL`, nunca `0` (uma etapa "não aconteceu" é diferente de "aconteceu e custou zero"). O valor líquido convivia em três formatos (`R$ 1.850,00`, `1850.00`, `1.200`) e foi tratado com expressão condicional antes do `CAST` para DECIMAL.

\* \*\*Categoria de produto:\*\* 18 grafias brutas mapeadas para 7 categorias padronizadas via `CASE WHEN`. A ordem importa: `MED` é testado antes de `RA`, porque "Ração Medicamentosa" contém "RA" e cairia na categoria errada. A collation padrão do MySQL já ignora acento e caixa, dispensando normalização extra.

\* \*\*Nome da loja:\*\* Padronizado sempre \*\*antes\*\* do JOIN com `dim\_loja`. Um `REPLACE` mecânico removeu o sufixo `/SC` e espaços duplos; depois um `CASE` manual resolveu as 3 grafias restantes (digitação, apelido e abreviação).

\* \*\*Desconto e canal:\*\* Como são domínios pequenos sem atributos, foram padronizados direto na carga da fato. No canal, a ordem importa: "WHATSAPP" contém "APP", então `WHATS` é testado antes de `APP`.

\* \*\*Rateio da praça:\*\* A tabela ponte guarda o `fator\_publico` (somando 1,00 por loja). O faturamento é multiplicado pelo fator antes de somar por praça, impedindo que uma loja que atende duas praças seja contada em dobro.



\---



\## 5. Como reproduzir o banco do zero

Execute os scripts na pasta `sql/`, nesta ordem, em um MySQL 8.0:



| Ordem | Arquivo | O que faz |

|---|---|---|

| \*\*1\*\* | `01-carga-staging.sql` | Cria o banco `dw\_pata\_amiga` e carrega as 3 tabelas de staging originais. |

| \*\*2\*\* | `02-dimensoes-prontas.sql` | Cria e carrega `dim\_tempo` (236 linhas) e `dim\_loja` (33 linhas); cria o esqueleto das próximas tabelas. |

| \*\*3\*\* | `03-dimensoes.sql` | Constrói `dim\_categoria`, `dim\_praca` e `bridge\_loja\_praca`. |

| \*\*4\*\* | `04-fato.sql` | Constrói `fato\_pedido` (4.044 linhas). |

| \*\*5\*\* | `05-perguntas.sql` | Executa as 5 consultas de negócio. |



> \*(Nota: `00-conferencia.sql` não faz parte da entrega — é apenas um script de auditoria).\*

> ⚠️ \*\*Atenção ao charset da conexão:\*\* Ao rodar via linha de comando, force utf8mb4 (`mysql -u root --default-character-set=utf8mb4 < 01-carga-staging.sql`). Sem isso, o client pode conectar em latin1 e corromper os acentos na carga.



\---



\## 6. As cinco respostas



\### P1 — Onde está o gargalo da entrega?



| Porte | Pedidos | Integ.→Separação | Separação→Nota | Nota→Despacho | Despacho→Entrega | Total até entrega |

|---|---|---|---|---|---|---|

| \*\*Grande\*\* | 1.763 | 2,0 | 0,6 | 3,3 | 2,0 | 7,9 |

| \*\*Média\*\* | 1.663 | 2,0 | 0,6 | 3,3 | 2,0 | 8,0 |

| \*\*Pequena\*\* | 615 | 3,0 | 0,7 | \*\*8,5\*\* | 2,9 | \*\*15,2\*\* |

| (sem loja) | 3 | 2,0 | 0,0 | 4,0 | 3,0 | 8,5 |



\*(Médias em dias, ignorando etapas não cumpridas).\*

O gargalo do processo, nos três portes, é o mesmo intervalo: \*\*nota fiscal → despacho para a transportadora\*\*. Mas ele não é igualmente distribuído: em lojas Pequenas esse intervalo sozinho leva 8,5 dias e puxa o tempo total de entrega para 15,2 dias (quase o dobro da rede). O problema não é a entrega em si; é o que acontece antes de a transportadora ser acionada.



\### P2 — Qual categoria concentra o faturamento?



| Categoria | Faturamento | % do total |

|---|---|---|

| \*\*Ração\*\* | R$ 1.076.202,55 | \*\*60,0%\*\* |

| Medicamento | R$ 305.904,03 | 17,1% |

| Petisco | R$ 128.590,16 | 7,2% |

| Serviço | R$ 94.001,37 | 5,2% |

| Higiene | R$ 92.314,45 | 5,2% |

| Acessório | R$ 64.661,39 | 3,6% |

| Brinquedo | R$ 31.634,56 | 1,8% |



\*\*Ração\*\* concentra 60% do faturamento da rede (mais que as outras seis categorias somadas) e é a categoria campeã nos três portes de loja sem exceção. É o produto-âncora da rede como um todo.



\### P3 — O desconto funciona igual em todo canal?



| Canal | Ticket médio SEM desc. | Ticket médio COM desc. | % do faturamento |

|---|---|---|---|

| \*\*App\*\* | R$ 167,63 | R$ 488,04 | \*\*30,8%\*\* |

| \*\*Site\*\* | R$ 189,68 | R$ 501,92 | 25,1% |

| \*\*Loja Física\*\* | R$ 197,55 | R$ 494,04 | 20,1% |

| \*\*WhatsApp\*\* | R$ 179,26 | R$ 514,33 | 10,5% |

| \*\*Telefone\*\* | R$ 195,23 | R$ 514,02 | 6,9% |



Em todos os canais o ticket médio com desconto é de \*\*2,5 a 3 vezes maior\*\* que sem desconto. Não há um canal onde o desconto "derruba" o ticket. Ressalva: os dados mostram correlação, não causa — não dá para afirmar que o desconto provoca o ticket maior; é possível que a loja conceda desconto preferencialmente em pedidos que já são grandes.



\### P4 — Qual praça de atendimento concentra o faturamento?



| Praça | Domicílios com pet | Faturamento rateado |

|---|---|---|

| \*\*Vale do Itajaí\*\* | 148.000 | R$ 633.746,09 |

| Grande Florianópolis | 132.000 | R$ 283.546,75 |

| Norte Industrial | 96.000 | R$ 175.431,90 |

| Litoral Sul | 58.000 | R$ 137.051,20 |

| Litoral Norte | 61.000 | R$ 128.872,75 |

| Extremo Oeste | 63.000 | R$ 98.359,18 |

| Carbonífera | 67.000 | R$ 88.707,42 |

| Serra Catarinense | 44.000 | R$ 80.477,64 |

| Meio-Oeste | 51.000 | R$ 58.955,63 |

| Foz do Itajaí | 74.000 | R$ 46.749,72 |

| Planalto Norte | 33.000 | R$ 31.100,84 |

| Planalto Serrano | 29.000 | R$ 29.323,10 |



\*(Soma rateada pelo `fator\_publico` da ponte + R$ 986,30 sem loja identificada = R$ 1.793.308,51, batendo o total da rede).\*

O \*\*Vale do Itajaí\*\* fatura \~R$4,28 por domicílio, quase o dobro da segunda colocada. A praça não lidera só porque é grande — ela converte desproporcionalmente mais que seu tamanho de mercado sugeriria.



\### P5 — Onde abrir a próxima loja, e limitações dos dados



\*\*Top Lojas por demanda relativa:\*\*

| Loja | População | Itens/mil hab. | Tempo médio |

|---|---|---|---|

| Rio dos Cedros | 11.322 | \*\*41,9\*\* | 14,2 dias |

| Presidente Getúlio | 16.359 | \*\*34,8\*\* | 14,2 dias |

| Ibirama | 18.613 | \*\*32,1\*\* | 15,4 dias |

| Itapoá | 20.586 | \*\*25,9\*\* | 15,4 dias |

| S. Amaro da Imperatriz | 22.357 | \*\*23,7\*\* | 15,9 dias |



As lojas com maior demanda relativa ao tamanho da cidade são consistemente \*\*cidades pequenas\*\* — e são justamente essas que carregam os piores tempos de entrega, reforçando o achado da P1.



\*\*Faturamento por faixa de franquia ATUAL:\*\*

| Faixa | Faturamento | % do total |

|---|---|---|

| Ouro | R$ 1.011.264,38 | 56,4% |

| Diamante | R$ 382.209,74 | 21,3% |

| Prata | R$ 314.812,03 | 17,6% |

| Bronze | R$ 84.036,06 | 4,7% |



\*Limitação:\* O cadastro guarda apenas a faixa atual (o histórico foi sobrescrito). Os 56% atribuídos a "Ouro" descrevem o faturamento da rede configurada \*hoje\*, não respondendo quanto a loja vendeu historicamente sob a mesma faixa.



\*\*O que ficou de fora (medido, não escondido):\*\*

| O que | Quantidade |

|---|---|

| Pedidos sem loja identificada | 3 |

| Entregas ainda não concluídas na janela | 1.953 (48,3%) |

| Pedidos com quantidade de itens em branco | 257 |

| Pedidos com valor em branco | 121 |



\---



\## 7. Recomendação final

Os dados apontam para duas coisas ao mesmo tempo:



\* \*\*Onde expandir:\*\* A demanda relativa é mais forte em cidades pequenas (Rio dos Cedros, Presidente Getúlio e Ibirama). A próxima loja tem mais chance de sucesso em uma cidade pequena com perfil semelhante, possivelmente na região do Vale do Itajaí, que mostrou capacidade de conversão acima da média.

\* \*\*O que resolver antes:\*\* Essas mesmas lojas pequenas sofrem o gargalo operacional da P1 (8,5 dias parados entre nota fiscal e despacho). Abrir uma loja nova desse porte sem endereçar esse gargalo reproduzirá o problema de entregas de mais de 15 dias.

\* \*\*O que não se pode afirmar:\*\* Não é possível apontar concorrência de mercado de outras marcas; não dá para afirmar que a faixa "Ouro" gera mais faturamento (pode ser o inverso: quem fatura mais vira Ouro); e os dados apontam \*onde\* o tempo se perde no gargalo operacional, mas não a causa-raiz (equipe, logística, etc).



\---



\## 8. Vídeo

\https://drive.google.com/file/d/1u2Lmr6IT_pepVpct1PPENCNOoh9mJpIC/view?usp=sharing

