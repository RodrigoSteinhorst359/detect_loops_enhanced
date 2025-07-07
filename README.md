# 🔍 Loop Detector Enhanced

**Detector avançado de loops de roteamento com relatórios HTML interativos e integração com Telegram.**


## 🚀 Instalação Rápida

### Pré-requisitos
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install fping nmap curl bc traceroute

# CentOS/RHEL/Fedora
sudo yum install fping nmap curl bc traceroute
```

### Download
```bash
# Clone o repositório
git clone https://github.com/seu-usuario/loop-detector-enhanced.git
cd loop-detector-enhanced

# Ou baixe diretamente
wget https://raw.githubusercontent.com/seu-usuario/loop-detector-enhanced/main/detect_loops_enhanced.sh
chmod +x detect_loops_enhanced.sh
```

## ⚙️ Configuração

### 1. Configuração Básica
```bash
# Edite o script e configure as linhas 11-12:
nano detect_loops_enhanced.sh

BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
CHAT_ID="-123456789"
```

### 2. Configuração do Telegram (Opcional)

#### Criar Bot:
1. Procure por `@BotFather` no Telegram
2. Envie `/newbot`
3. Escolha um nome: `Network Monitor Bot`
4. Escolha um username: `networkmonitor_bot`
5. Copie o **token** gerado

#### Obter Chat ID:
1. Procure por `@userinfobot` no Telegram
2. Envie qualquer mensagem
3. Copie o **User ID** (seu Chat ID)

## 💫 Uso

### Comandos Básicos
```bash
# Detecção básica de loops
./detect_loops_enhanced.sh 192.168.1.0/24

# Com detecção de roteamento assimétrico
./detect_loops_enhanced.sh 192.168.1.0/24 --asymmetric-routing

# Com detecção de problemas MTU
./detect_loops_enhanced.sh 192.168.1.0/24 --mtu-problems

# Análise completa (todos os testes)
./detect_loops_enhanced.sh 192.168.1.0/24 --deep-scan
```

### Comandos Avançados
```bash
# Sobrescrever configuração do Telegram
./detect_loops_enhanced.sh 192.168.1.0/24 "outro_token" "outro_chat"

# Desabilitar Telegram temporariamente
ENABLE_TELEGRAM=false ./detect_loops_enhanced.sh 192.168.1.0/24

# Desabilitar relatório HTML
ENABLE_HTML_REPORT=false ./detect_loops_enhanced.sh 192.168.1.0/24
```

## 📊 Exemplos de Saída

### Terminal
```
╔══════════════════════════════════════════════╗
║        LOOP DETECTOR ENHANCED v2.0        ║
╚══════════════════════════════════════════════╝

[2025-07-07 15:30:15] Iniciando varredura em 192.168.1.0/24

Testes habilitados:
  ✅ Detecção de loops de roteamento
  ✅ Detecção de roteamento assimétrico
  ✅ Detecção de problemas de MTU

✅ Todas as dependências estão instaladas
✅ 254 IPs serão testados

🔍 Iniciando detecção de loops...
Progresso: [100%] Testando 192.168.1.254... OK

╔══════════════════════════════════════════════╗
║                 RESUMO FINAL                 ║
╚══════════════════════════════════════════════╝
📊 Total de IPs testados: 254
✅ IPs OK: 252
⚠️  Loops detectados: 2
🔄 Roteamento assimétrico: 0
📏 Problemas MTU: 0
📈 Taxa de loops: 0.79%
⏱️  Duração: 45s
```

### Telegram
```
🔍 Loop Detector Enhanced v2.0

📊 Resumo da Varredura:
• Rede: 192.168.1.0/24
• Total testados: 254 IPs
• IPs OK: 252
• Loops detectados: 2
• Taxa de loops: 0.79%
• Duração: 45s

⚠️ Problemas encontrados:
🔄 192.168.1.15 (Loop)
🔄 192.168.1.23 (Loop)

📎 Relatórios detalhados em anexo
⏰ 07/07/2025 15:30:45
```

**+ 2 arquivos anexos:**
- 📋 `loop_report_YYYYMMDD_HHMMSS.txt` (relatório técnico)
- 🌐 `loop_report_YYYYMMDD_HHMMSS.html` (relatório visual)

## 📈 Relatório HTML

O relatório HTML inclui:

### 📊 Dashboard Interativo
- **Cards resumo** com estatísticas principais
- **Gráfico de pizza animado** com Chart.js
- **Lista detalhada** de problemas encontrados
- **Recomendações técnicas** específicas
- **Design responsivo** para todos os dispositivos


## 🔄 Automação

### Cron Jobs
```bash
# Monitoramento diário às 08:00
0 8 * * * cd /path/to/script && ./detect_loops_enhanced.sh 192.168.1.0/24

# Monitoramento a cada 30 minutos
*/30 * * * * cd /path/to/script && ./detect_loops_enhanced.sh 192.168.1.0/24

# Múltiplas redes
0 8 * * * cd /path/to/script && ./detect_loops_enhanced.sh 192.168.1.0/24
5 8 * * * cd /path/to/script && ./detect_loops_enhanced.sh 10.0.0.0/16
10 8 * * * cd /path/to/script && ./detect_loops_enhanced.sh 172.16.0.0/12
```



## 🔧 Casos de Uso

### 1. 🏢 Monitoramento Corporativo
```bash
# Redes críticas com deep scan
./detect_loops_enhanced.sh 10.0.0.0/8 --deep-scan
./detect_loops_enhanced.sh 172.16.0.0/12 --deep-scan
```

### 2. 🔍 Troubleshooting
```bash
# Quando há problemas de conectividade
./detect_loops_enhanced.sh 192.168.1.0/24 --asymmetric-routing
```

### 3. 📋 Relatórios Executivos
```bash
# Gera relatório HTML para apresentação
./detect_loops_enhanced.sh 10.0.0.0/16
# Abrir arquivo HTML gerado em: /tmp/loop_detector_*/loop_report_*.html
```

### 4. ⚡ Monitoramento Contínuo
```bash
# Script para monitorar múltiplas redes
#!/bin/bash
networks=("192.168.1.0/24" "10.0.0.0/16" "172.16.0.0/12")
for network in "${networks[@]}"; do
    ./detect_loops_enhanced.sh "$network" --deep-scan
    sleep 60
done
```

## 🛠️ Opções Avançadas

| Opção | Descrição | Exemplo |
|-------|-----------|---------|
| `--asymmetric-routing` | Detecta rotas diferentes ida/volta | `./script.sh 192.168.1.0/24 --asymmetric-routing` |
| `--mtu-problems` | Detecta problemas de MTU/fragmentação | `./script.sh 192.168.1.0/24 --mtu-problems` |
| `--deep-scan` | Executa todos os testes avançados | `./script.sh 192.168.1.0/24 --deep-scan` |
| `--help` | Mostra ajuda completa | `./script.sh --help` |

## 🔍 Solução de Problemas

### Dependências em Falta
```bash
# O script verifica automaticamente e informa:
❌ Dependências em falta: fping nmap
Instale com: sudo apt install fping nmap
```

### Telegram Não Configurado
```bash
⚠️ Configurações do Telegram não definidas
Configure BOT_TOKEN e CHAT_ID no script ou passe como parâmetros
Executando sem notificações do Telegram...
```

### CIDR Inválido
```bash
Erro: CIDR inválido. Use o formato IP/MASK (ex: 192.168.1.0/24)
```

### Permissões
```bash
# Se necessário, execute com privilégios:
sudo ./detect_loops_enhanced.sh 192.168.1.0/24
```

## 🎯 Performance

| Rede | IPs | Tempo Estimado | Memória |
|------|-----|----------------|---------|
| /30 | 4 | ~5s | ~2MB |
| /28 | 16 | ~15s | ~3MB |
| /24 | 254 | ~45s | ~5MB |
| /20 | 4,096 | ~15min | ~10MB |
| /16 | 65,536 | ~4h | ~20MB |

## 🚨 Limitações

- **Fping required**: Script depende do fping para detecção
- **Root privileges**: Alguns testes podem precisar de sudo
- **Network timeouts**: Redes lentas podem aumentar o tempo
- **Large networks**: Redes /16 ou maiores podem demorar horas


## 🙏 Créditos

- **fping**: Ferramenta principal para detecção de loops
- **Chart.js**: Gráficos interativos no HTML
- **Telegram Bot API**: Integração de notificações




---

<div align="center">

**⭐ Se este projeto foi útil, deixe uma estrela! ⭐**



</div>
