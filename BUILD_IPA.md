# Gerar o IPA não assinado sem Mac, usando GitHub Actions

Este repositório possui `.github/workflows/build-ios.yml`, que executa Xcode em um runner macOS para compilar a versão iPhone do Chess Trainer. **O build não foi executado neste ambiente Linux**, portanto pode ser necessário corrigir erros revelados pelo primeiro build real.

## Pelo Windows

1. Entre em https://github.com/new e crie um repositório vazio (pode ser privado, observando as cotas do GitHub Actions para runners macOS).
2. Extraia o ZIP do projeto no Windows. Verifique que o conteúdo da pasta inclui `.github`, `iOS`, `WindowsServer` e `project.yml`.
3. Abra PowerShell **dentro da pasta ChessTrainerStarter**. Com Git instalado, execute, trocando a URL pela do seu repositório:

   ```powershell
   git init
   git branch -M main
   git add .
   git commit -m "Projeto inicial iOS"
   git remote add origin https://github.com/SEU_USUARIO/SEU_REPOSITORIO.git
   git push -u origin main
   ```

   Se o Git pedir identidade: `git config --global user.name "Seu Nome"` e `git config --global user.email "seu-email@example.com"`.

4. No site do repositório, abra **Actions → Compilar IPA iOS sem assinatura → Run workflow → Run workflow**.
5. Aguarde a execução. Se a compilação ficar verde, abra a execução e baixe o artefato **ChessTrainer-unsigned-ipa**. O download do Actions costuma ser um ZIP com o arquivo `ChessTrainer-unsigned.ipa` dentro.
6. Se a compilação falhar, consulte o log da etapa `Compilar arm64 para iPhone` para saber o motivo.

## Limitações

- Um IPA não assinado **não instala diretamente no iPhone**. Será necessária assinatura adequada tanto do app quanto da extensão ReplayKit; App Groups podem exigir entitlements/profiles compatíveis.
- O modo desenvolvedor no iPhone não substitui a assinatura.
- Este protótipo não possui a mini janela PiP implementada, e não incorpora o motor Stockfish: depende do servidor Windows na mesma rede.
- A detecção foi projetada para treino e revisão, não assistência em tempo real em partidas competitivas online.
