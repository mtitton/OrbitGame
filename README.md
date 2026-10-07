# OrbitGame — V6.3.1

Versão consolidada do Orbit com Game Center preparado para o App Store Connect usando os identificadores definitivos do projeto.

## Identificadores definitivos

- Bundle ID: `com.marcustitton.orbitgame`
- Leaderboard Melhor Score: `com.marcustitton.orbitgame.leaderboard.best`
- Leaderboard Daily Orbit: `com.marcustitton.orbitgame.leaderboard.daily`

Achievements previstos:

- `com.marcustitton.orbitgame.achievement.first_orbit`
- `com.marcustitton.orbitgame.achievement.getting_serious`
- `com.marcustitton.orbitgame.achievement.orbit_master`
- `com.marcustitton.orbitgame.achievement.untouchable`
- `com.marcustitton.orbitgame.achievement.combo_master`
- `com.marcustitton.orbitgame.achievement.addicted`

## O que mudou na V6.3.1

- Bundle ID alterado para `com.marcustitton.orbitgame` em Debug e Release.
- Build number atualizado para 7.
- IDs do Game Center atualizados para os IDs definitivos criados no App Store Connect.
- Removida a dependência do `GKAccessPoint.trigger(leaderboardID:...)`, que exige disponibilidade mais recente.
- O ranking agora é apresentado com `GKGameCenterViewController`, compatível com o deployment target iOS 17.
- Fluxo de login + abertura de ranking refeito: após autenticar, o app aguarda a tela de login ser realmente dispensada antes de abrir o leaderboard.
- O rodapé da Home é reconstruído do zero sempre que volta a ficar visível, evitando o desaparecimento isolado de `RANKING`.
- `RANKING` ganhou uma linha própria, acima de `MISSÕES / TEMAS / STATS`, afastada da home indicator.
- Ao fechar o Game Center, a Home força a reconstrução do rodapé.
- Daily Orbit e missões diárias agora usam o dia em UTC, alinhando a sequência diária entre jogadores no mundo todo e com o leaderboard recorrente da Apple.

## Game Center no App Store Connect

Os dois leaderboards precisam existir com estes IDs:

1. Classic leaderboard
   - Reference Name: Orbit Best Score
   - ID: `com.marcustitton.orbitgame.leaderboard.best`
   - Integer / Best Score / High to Low

2. Recurring leaderboard
   - Reference Name: Daily Orbit
   - ID: `com.marcustitton.orbitgame.leaderboard.daily`
   - Integer / Best Score / High to Low
   - recorrência diária

Na primeira submissão com Game Center, associe os componentes à mesma versão do app no App Store Connect antes de enviar para revisão.

## Teste recomendado

1. Abra o app.
2. Toque em `RANKING`.
3. Se necessário, faça login no Game Center.
4. O leaderboard deve abrir automaticamente após o login.
5. Feche o Game Center e toque em `RANKING` novamente — deve abrir direto.
6. Feche completamente o Orbit, abra novamente e confirme que `RANKING` continua visível.
7. Faça uma partida no modo Normal e valide o envio do melhor score.
8. Faça uma partida no Daily Orbit e valide o score no leaderboard diário quando o componente estiver disponível para a build.

## Observação sobre achievements

O código mantém a lógica de achievements preparada, mas eles podem ser criados no App Store Connect em uma etapa posterior. Caso ainda não existam, a falha de envio de achievement não interfere nos leaderboards nem no gameplay.


## V6.3.1 — Home layout polish
- Footer split into four independent vertical rows.
- Safe-area-aware positioning for Missions / Themes / Stats.
- Normal/Daily selector no longer overlaps the start instruction.
- Ranking remains on its own row.
- Compact-height iPhones lift the orbit slightly to preserve spacing.
