# TDE — MapScanner v1.0

Projeto acadêmico (PUCPR — Explosão e Partículas) em **Godot 4.6** (2D, GDScript).
Implementa o **MapScanner**, um minimapa de exploração para jogos de plataforma 2D:

- névoa de guerra por grade de células (só aparece o que a câmera já mostrou);
- terreno estático e dinâmico (portas e paredes atualizadas por eventos);
- marcadores temporários de inimigos, colecionáveis e plataformas móveis;
- regiões secretas com condições de desbloqueio E/OU;
- progresso salvo em `user://` com gravação segura (.tmp/.bak).

A documentação completa está em [`docs/MapScanner_TDE_documentacao.pdf`](docs/MapScanner_TDE_documentacao.pdf).

## Como abrir

1. Instale a Godot **4.6** (versão padrão, não a .NET).
2. Na Godot, clique em **Importar** e escolha o arquivo `project.godot` desta pasta.
3. A primeira abertura reimporta os assets (a pasta `.godot/` não vai para o Git).

## Cenas

| Cena | O que é |
|---|---|
| `Scenes/game.tscn` | Fase principal (abre ao rodar o projeto com F5) |
| `Scenes/map_scanner_test.tscn` | Fase de teste com um exemplo de cada mecânica (abra e rode com F6) |

## Controles

| Tecla | Ação |
|---|---|
| ← / → | Andar (Shift para correr) |
| Espaço | Pular (no ar, pulo duplo) |
| Q | Atacar (mata inimigo / quebra a parede de tijolos de perto) |
| F6 | Abrir/fechar a porta (fase de teste) |
| F7 | Quebrar a parede (fase de teste) |
| F9 | Apagar o progresso do minimapa (fase de teste) |

## Estrutura

```
Scenes/                 cenas
Scripts/player.gd       jogador (movimento, pulo duplo, coyote time, ataque)
Scripts/MapScanner/     componentes do minimapa
Scripts/MapScanner/Test objetos usados só na fase de teste
Assets/                 sprites, texturas e fontes
docs/                   documentação em PDF
```

## Créditos dos assets

- Sprites (Samurai, Fighter, Shinobi) — CraftPix, <https://craftpix.net/file-licenses/>
- AutoSprite Free Asset Library — CC0 1.0 (ver `LICENSE.txt`)
- Fonte DigitalDisco — <https://www.dafont.com/digital-disco.font117>
- `Assets/Wall.jpg` — (preencher fonte e licença)
- `Assets/Wall_1.jpg` — prévia com marca d'água; **substituir ou licenciar antes de tornar o repositório público**

Os assets de terceiros continuam sob as licenças dos autores originais.
