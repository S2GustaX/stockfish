# Chess Trainer — projeto Swift inicial (iOS 17+)

Protótipo **para treino e revisão**, com captura de tela autorizada pelo ReplayKit, calibração por screenshot, reconhecimento heurístico das mudanças do tabuleiro, e análises de xadrez feitas pelo **Stockfish executado no Windows**. Preferências iniciais: **ELO ~2500**, **profundidade 16**, cor/orientação **automática**, setas e avaliação **ativadas**.

> **Status: projeto-fonte experimental, não aplicativo IPA pronto.** Parte da lógica de posições foi testada em Swift no Linux. O app iOS não foi compilado em Xcode nem testado num iPhone neste ambiente. O reconhecimento visual depende da aparência da interface e não tem a robustez de um modelo treinado com muitas posições.

## O que já foi implementado

- App SwiftUI com tela de configurações e visualização de tabuleiro, lances sugeridos e avaliação.
- Importação de screenshot pelo seletor do iOS, moldura ajustável e **calibração em posição inicial padrão** (32 peças nas casas iniciais).
- Detecção automática da orientação inicial por cor das peças; alternativa para configurar brancas/pretas manualmente.
- Templates aprendidos a partir de cada peça da posição inicial; scanner compara casas da captura em sequência.
- Extensão **ReplayKit Broadcast Upload** que recebe quadros da tela e tenta detectar mudanças do tabuleiro a cada ~0,85 s.
- Rastreador de lances: aguarda a mesma posição em duas capturas, tenta identificar origem/destino, produz FEN e conserva lado a jogar, roque e en passant. Cobre movimentos normais e alguns especiais, mas **não faz validação completa de legalidade no iOS**.
- Servidor Python no Windows (`python-chess` + executável Stockfish) usando UCI: respeita ELO configurável **quando suportado pelo motor**, profundidade 16, avaliação em centipeões e principal variation.
- Cliente HTTP para enviar a posição ao computador Windows na mesma rede, com token de autenticação.
- Workflow do GitHub Actions para tentar compilar uma **IPA não assinada** em macOS, a ser assinada posteriormente.

## Limitações importantes

1. **Não há mini-janela PiP flutuante funcional** neste protótipo. O iOS restringe interfaces desenhadas sobre outros apps; a extensão de transmissão captura a tela, mas o aplicativo principal pode ser suspenso quando você troca de app. Os resultados são consultáveis quando o Chess Trainer está em primeiro plano.
2. **Não há Stockfish embarcado no IPA.** As análises dependem do servidor no seu Windows, que precisa estar ligado e na mesma rede. Um módulo Stockfish estático para iOS pode ser investigado como evolução (com respeito à GPLv3), mas não está incluído.
3. O reconhecimento **exige calibração com o tabuleiro na posição inicial padrão**. Não comece a partir de uma posição já modificada; ele não faz leitura visual sem treinamento inicial. Não mude zoom, tema, orientação ou resolução depois de calibrar. Setas, pop-ups e destaques podem prejudicar a classificação.
4. O reconhecimento não foi treinado/testado em muitas capturas; pode errar peças e perder jogadas rápidas. Em caso de desincronização, faça nova calibração no início de uma partida de treino.
5. A comunicação HTTP é **sem criptografia**, indicada apenas em uma rede Wi-Fi confiável, usando token. Para distribuição, substituir por HTTPS e permissões de rede mais restritas.
6. **ReplayKit com App Groups requer provisionamento compatível** para compartilhar calibração e resultado entre o app e a extensão. Modo desenvolvedor do iPhone **não** elimina exigência de certificado de assinatura, nem garante compatibilidade com entitlements do App Group. A assinatura gratuita (Personal Team) pode não oferecer a capacidade necessária.
7. Usar sugestões de engine durante partidas online contra outras pessoas viola as regras de fair play do Chess.com; mantenha o projeto no contexto de análise e treino.

## Como iniciar o servidor Stockfish no Windows

1. Instale Python 3.11+ no Windows e baixe **Stockfish para Windows** de uma fonte oficial/confiável. Extraia o `.exe` para uma pasta à sua escolha.
2. Abra PowerShell na pasta `WindowsServer` e execute:

   ```powershell
   py -m pip install -r requirements.txt
   py server.py --engine "C:\Stockfish\stockfish.exe" --token "mude-para-um-token-com-pelo-menos-12-caracteres"
   ```

3. No PowerShell, rode `ipconfig` e localize o **endereço IPv4 da rede Wi-Fi**, por exemplo `192.168.1.10` (exemplo, não use esse IP sem verificar). Autorize conexões recebidas na porta 8765 no Firewall do Windows, de preferência somente para a rede privada.
4. No aplicativo, preencha `http://IP-REAL-DO-PC:8765` e o **mesmo token**, depois toque em *Salvar configurações*. O iPhone e o PC devem estar na mesma Wi-Fi.
5. Teste pelo navegador do iPhone: `http://IP-REAL-DO-PC:8765/health` (endpoint de diagnóstico; não transmite resultados).

## Preparar o projeto Swift no macOS

O projeto utiliza [XcodeGen](https://github.com/yonaskolb/XcodeGen). Pode ser compilado em um Mac próprio/emprestado ou numa máquina macOS na nuvem:

```bash
brew install xcodegen
xcodegen generate
open ChessTrainer.xcodeproj
```

No Xcode:

- Selecione ambos os targets (`ChessTrainer` e `BroadcastExtension`) e defina uma **Team de assinatura válida**.
- Substitua os bundle IDs `com.example.chesstrainer` e `com.example.chesstrainer.broadcast` por identificadores próprios.
- Substitua `group.com.example.chesstrainer` pelos **mesmos valores reais** nos dois `.entitlements` e em `iOS/Shared/Models.swift`; atualize `AppIdentity.broadcastBundle` com o bundle ID real.
- Configure **App Groups** nos dois targets com o mesmo grupo e certifique-se de que o perfil de provisionamento suporta o entitlement.
- No dispositivo, ative o modo desenvolvedor quando necessário para executar instalações de desenvolvimento.
- Faça primeiro `Product > Build`, instale no iPhone e valide o seletor de transmissão. Depois considere exportar o IPA assinado.

### Sem Mac: GitHub Actions

Ao subir estes arquivos para um repositório GitHub, a ação `.github/workflows/build-ios.yml` executa Xcode no runner macOS e, **se o build passar**, publica um arquivo `ChessTrainer-unsigned.ipa` como artefato.

**Uma IPA não assinada não é instalável diretamente**. Para gerar um IPA que funcione com App Groups é necessário assinar o app **e a extensão** com certificados, profiles e entitlements compatíveis. Sideloadly ou AltStore podem não conseguir preservar as capacidades exigidas pelo protótipo com Apple IDs gratuitos.

## Uso de treino

1. Abra um tabuleiro com **posição inicial padrão** e faça uma captura da tela.
2. Abra o Chess Trainer; importe essa captura, ajuste a moldura para corresponder apenas às 64 casas e calibre.
3. Ajuste o URL/token do Stockfish no Windows e salve.
4. Toque no seletor de transmissão ReplayKit, escolha `Chess Trainer Capture` e inicie a transmissão.
5. Volte ao tabuleiro de treino, jogue e depois abra o Chess Trainer para inspecionar as posições/lances reconhecidos e a análise recebida.

Se houver erro de leitura, ajuste o quadro de captura ou calibre novamente. Nesta versão os detalhes da posição não aparecem sobre o Chess.com.

## Verificações disponíveis fora do macOS

Para testar a parte independente do iOS, caso haja Swift instalado:

```bash
swiftc iOS/Shared/Models.swift iOS/Shared/PositionTracker.swift \
  Tests/PositionTrackerTests.swift -o chess_tracker_test
./chess_tracker_test
python -m py_compile WindowsServer/server.py
```

A pasta **não inclui executáveis Stockfish**. Stockfish é um projeto open source sob a GPLv3; verifique licenças, atribuições e obrigações de redistribuição antes de empacotar ou distribuir binários.
