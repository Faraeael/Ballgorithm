# T08C financial audit (generated)

Read-only reproduction of the T08B-R1 24-league payroll audit using the implemented T08C financial domain. Regenerate with `dart run tool/t08c_financial_audit.dart` from `packages/simulation_core`. No production source is modified by the run.

### Variant A: human picks first available
Pre-draft cap payroll: tanking 6950/8200/8289/9500; playoff 21200/24400/24177/27300; contender 32600/37400/37593/40400; playIn 12200/14700/14707/16650
Post-draft cap payroll: tanking 7750/10650/10572/12000; playoff 21200/24400/24221/27300; contender 32600/37400/37593/40400; playIn 13450/16100/16057/17850
Post-draft cash payroll: tanking 7750/10650/10587/12000; playoff 21200/24650/24402/27550; contender 32600/37400/37593/40400; playIn 13450/16150/16217/18100
Post-draft cap room: tanking 29000/30350/30428/33250; playoff 13700/16600/16779/19800; contender 600/3600/3408/8400; playIn 23150/24900/24943/27550
Year 2 cap payroll: tanking 7558/10394/10446/12598; playoff 13230/18165/18200/25200; contender 12915/19320/20169/26460; playIn 7612/12547/12732/16484
Year 3 cap payroll: tanking 0/2755/2516/2755; playoff 0/0/0/0; contender 0/0/0/0; playIn 0/1323/1488/2424
cap over: 0 []
cannot add one minimum: 0 []
cannot add two minimum: 8 [team-23=600, team-23=600, team-23=600, team-23=600, team-23=600, team-23=600, team-23=600, team-23=600]
human pre/post payroll: 7750..39200 / 7750..39200
human cap room: 1800..33250
human 3-year cash: 81267..96955
career validations: 48
contract scenarios (contracts/rookie): {initialContracts/rookie: 360/0, draftOnlyContracts: 360/0, afterAiContracts/rookie: 392/32, rosterPlayers: 392}

Reference table (pre-draft, seed 20261028 team-1 Play-In)
| team-1 | AUR | Play-In Contender | 12 | 0 | 13450 | 0 | 13450 | 27550 | 47000 | 34250 |
| team-2 | IRV | Playoff Team | 12 | 0 | 24500 | 0 | 24500 | 16500 | 52000 | 31200 |
| team-3 | PMT | Playoff Team | 12 | 0 | 26300 | 0 | 26300 | 14700 | 52000 | 29400 |
| team-4 | RSC | Playoff Team | 12 | 0 | 23600 | 0 | 23600 | 17400 | 52000 | 32100 |
| team-5 | NGL | Championship Contender | 12 | 0 | 32600 | 0 | 32600 | 8400 | 57000 | 31100 |
| team-6 | SLK | Playoff Team | 12 | 0 | 26000 | 0 | 26000 | 15000 | 52000 | 29700 |
| team-7 | VDU | Tanking / Rebuilding | 12 | 0 | 7850 | 0 | 7850 | 33150 | 42000 | 31850 |
| team-8 | CBE | Championship Contender | 12 | 0 | 37100 | 0 | 37100 | 3900 | 57000 | 26600 |
| team-9 | MCV | Playoff Team | 12 | 0 | 22700 | 0 | 22700 | 18300 | 52000 | 33000 |
| team-10 | CRM | Play-In Contender | 12 | 0 | 14250 | 0 | 14250 | 26750 | 47000 | 33450 |
| team-11 | SPA | Tanking / Rebuilding | 12 | 0 | 8200 | 0 | 8200 | 32800 | 42000 | 31500 |
| team-12 | TLW | Tanking / Rebuilding | 12 | 0 | 8800 | 0 | 8800 | 32200 | 42000 | 30900 |
| team-13 | BSC | Tanking / Rebuilding | 12 | 0 | 8700 | 0 | 8700 | 32300 | 42000 | 31000 |
| team-14 | GCS | Play-In Contender | 12 | 0 | 14000 | 0 | 14000 | 27000 | 47000 | 33700 |
| team-15 | HPA | Playoff Team | 12 | 0 | 22800 | 0 | 22800 | 18200 | 52000 | 32900 |
| team-16 | CLS | Play-In Contender | 12 | 0 | 15650 | 0 | 15650 | 25350 | 47000 | 32050 |
| team-17 | GBG | Playoff Team | 12 | 0 | 26500 | 0 | 26500 | 14500 | 52000 | 29200 |
| team-18 | DMV | Play-In Contender | 12 | 0 | 13850 | 0 | 13850 | 27150 | 47000 | 33850 |
| team-19 | KSM | Championship Contender | 12 | 0 | 39300 | 0 | 39300 | 1700 | 57000 | 24400 |
| team-20 | HCN | Play-In Contender | 12 | 0 | 14750 | 0 | 14750 | 26250 | 47000 | 32950 |
| team-21 | WWR | Tanking / Rebuilding | 12 | 0 | 7700 | 0 | 7700 | 33300 | 42000 | 32000 |
| team-22 | SFS | Championship Contender | 12 | 0 | 37400 | 0 | 37400 | 3600 | 57000 | 26300 |
| team-23 | OHS | Tanking / Rebuilding | 12 | 0 | 8450 | 0 | 8450 | 32550 | 42000 | 31250 |
| team-24 | CCB | Tanking / Rebuilding | 12 | 0 | 8000 | 0 | 8000 | 33000 | 42000 | 31700 |
| team-25 | FWG | Playoff Team | 12 | 0 | 25000 | 0 | 25000 | 16000 | 52000 | 30700 |
| team-26 | BWR | Play-In Contender | 12 | 0 | 15200 | 0 | 15200 | 25800 | 47000 | 32500 |
| team-27 | ISL | Playoff Team | 12 | 0 | 24800 | 0 | 24800 | 16200 | 52000 | 30900 |
| team-28 | CVF | Play-In Contender | 12 | 0 | 15550 | 0 | 15550 | 25450 | 47000 | 32150 |
| team-29 | SLV | Play-In Contender | 12 | 0 | 14400 | 0 | 14400 | 26600 | 47000 | 33300 |
| team-30 | VFT | Championship Contender | 12 | 0 | 37100 | 0 | 37100 | 3900 | 57000 | 26600 |

### Variant B: human picks AI strategy
Pre-draft cap payroll: tanking 6950/8200/8289/9500; playoff 21200/24400/24177/27300; contender 32600/37400/37593/40400; playIn 12200/14700/14707/16650
Post-draft cap payroll: tanking 7750/10650/10547/12000; playoff 21200/24400/24221/27300; contender 32600/37400/37593/40400; playIn 13450/16100/16041/17850
Post-draft cash payroll: tanking 7750/10650/10571/12000; playoff 21200/24600/24402/27550; contender 32600/37400/37593/40400; playIn 13450/16150/16203/18100
Post-draft cap room: tanking 29000/30350/30453/33250; playoff 13700/16600/16779/19800; contender 600/3600/3408/8400; playIn 23150/24900/24959/27550
Year 2 cap payroll: tanking 7558/10340/10420/12598; playoff 13230/18165/18200/25200; contender 12915/19320/20169/26460; playIn 7402/12547/12715/16484
Year 3 cap payroll: tanking 0/2755/2489/2755; playoff 0/0/0/0; contender 0/0/0/0; playIn 0/1323/1470/2424
cap over: 0 []
cannot add one minimum: 0 []
cannot add two minimum: 8 [team-23=600, team-23=600, team-23=600, team-23=600, team-23=600, team-23=600, team-23=600, team-23=600]
human pre/post payroll: 7750..39200 / 7750..39200
human cap room: 1800..33250
human 3-year cash: 81267..96955
career validations: 48
contract scenarios (contracts/rookie): {initialContracts/rookie: 360/0, draftOnlyContracts: 360/0, afterAiContracts/rookie: 392/32, rosterPlayers: 392}

Reference table (pre-draft, seed 20261028 team-1 Play-In)
| team-1 | AUR | Play-In Contender | 12 | 0 | 13450 | 0 | 13450 | 27550 | 47000 | 34250 |
| team-2 | IRV | Playoff Team | 12 | 0 | 24500 | 0 | 24500 | 16500 | 52000 | 31200 |
| team-3 | PMT | Playoff Team | 12 | 0 | 26300 | 0 | 26300 | 14700 | 52000 | 29400 |
| team-4 | RSC | Playoff Team | 12 | 0 | 23600 | 0 | 23600 | 17400 | 52000 | 32100 |
| team-5 | NGL | Championship Contender | 12 | 0 | 32600 | 0 | 32600 | 8400 | 57000 | 31100 |
| team-6 | SLK | Playoff Team | 12 | 0 | 26000 | 0 | 26000 | 15000 | 52000 | 29700 |
| team-7 | VDU | Tanking / Rebuilding | 12 | 0 | 7850 | 0 | 7850 | 33150 | 42000 | 31850 |
| team-8 | CBE | Championship Contender | 12 | 0 | 37100 | 0 | 37100 | 3900 | 57000 | 26600 |
| team-9 | MCV | Playoff Team | 12 | 0 | 22700 | 0 | 22700 | 18300 | 52000 | 33000 |
| team-10 | CRM | Play-In Contender | 12 | 0 | 14250 | 0 | 14250 | 26750 | 47000 | 33450 |
| team-11 | SPA | Tanking / Rebuilding | 12 | 0 | 8200 | 0 | 8200 | 32800 | 42000 | 31500 |
| team-12 | TLW | Tanking / Rebuilding | 12 | 0 | 8800 | 0 | 8800 | 32200 | 42000 | 30900 |
| team-13 | BSC | Tanking / Rebuilding | 12 | 0 | 8700 | 0 | 8700 | 32300 | 42000 | 31000 |
| team-14 | GCS | Play-In Contender | 12 | 0 | 14000 | 0 | 14000 | 27000 | 47000 | 33700 |
| team-15 | HPA | Playoff Team | 12 | 0 | 22800 | 0 | 22800 | 18200 | 52000 | 32900 |
| team-16 | CLS | Play-In Contender | 12 | 0 | 15650 | 0 | 15650 | 25350 | 47000 | 32050 |
| team-17 | GBG | Playoff Team | 12 | 0 | 26500 | 0 | 26500 | 14500 | 52000 | 29200 |
| team-18 | DMV | Play-In Contender | 12 | 0 | 13850 | 0 | 13850 | 27150 | 47000 | 33850 |
| team-19 | KSM | Championship Contender | 12 | 0 | 39300 | 0 | 39300 | 1700 | 57000 | 24400 |
| team-20 | HCN | Play-In Contender | 12 | 0 | 14750 | 0 | 14750 | 26250 | 47000 | 32950 |
| team-21 | WWR | Tanking / Rebuilding | 12 | 0 | 7700 | 0 | 7700 | 33300 | 42000 | 32000 |
| team-22 | SFS | Championship Contender | 12 | 0 | 37400 | 0 | 37400 | 3600 | 57000 | 26300 |
| team-23 | OHS | Tanking / Rebuilding | 12 | 0 | 8450 | 0 | 8450 | 32550 | 42000 | 31250 |
| team-24 | CCB | Tanking / Rebuilding | 12 | 0 | 8000 | 0 | 8000 | 33000 | 42000 | 31700 |
| team-25 | FWG | Playoff Team | 12 | 0 | 25000 | 0 | 25000 | 16000 | 52000 | 30700 |
| team-26 | BWR | Play-In Contender | 12 | 0 | 15200 | 0 | 15200 | 25800 | 47000 | 32500 |
| team-27 | ISL | Playoff Team | 12 | 0 | 24800 | 0 | 24800 | 16200 | 52000 | 30900 |
| team-28 | CVF | Play-In Contender | 12 | 0 | 15550 | 0 | 15550 | 25450 | 47000 | 32150 |
| team-29 | SLV | Play-In Contender | 12 | 0 | 14400 | 0 | 14400 | 26600 | 47000 | 33300 |
| team-30 | VFT | Championship Contender | 12 | 0 | 37100 | 0 | 37100 | 3900 | 57000 | 26600 |
