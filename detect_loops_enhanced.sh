#!/bin/bash

# ============================================================
# DETECTOR DE LOOPS DE ROTEAMENTO COM RELATÓRIOS HTML
# Versão: 2.0 Enhanced - CORRIGIDO
# ============================================================

# ============================================================
# CONFIGURAÇÕES DO TELEGRAM - EDITE AQUI
# ============================================================
BOT_TOKEN="SEU_BOT_TOKEN_AQUI"
CHAT_ID="SEU_CHAT_ID_AQUI"
ENABLE_TELEGRAM=true  # true/false para ativar/desativar Telegram
ENABLE_HTML_REPORT=true  # true/false para gerar relatório HTML
# ============================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variáveis globais
SCRIPT_VERSION="2.0"
START_TIME=$(date +%s)
REPORT_DATE=$(date +'%Y%m%d_%H%M%S')
TEMP_DIR="/tmp/loop_detector_$$"
HTML_REPORT_FILE=""
TXT_REPORT_FILE=""

# Função para mostrar ajuda
show_help() {
    echo "Loop Detector Enhanced v$SCRIPT_VERSION"
    echo "========================================"
    echo ""
    echo "Uso: $0 <CIDR> [BOT_TOKEN] [CHAT_ID] [OPÇÕES]"
    echo ""
    echo "Parâmetros:"
    echo "  CIDR        Bloco de rede a ser varrido (ex: 198.18.0.0/24)"
    echo "  BOT_TOKEN   Token do bot do Telegram (opcional - pode ser configurado no script)"
    echo "  CHAT_ID     ID do chat do Telegram (opcional - pode ser configurado no script)"
    echo ""
    echo "Opções:"
    echo "  --asymmetric-routing    Detecta roteamento assimétrico"
    echo "  --mtu-problems         Detecta problemas de MTU"
    echo "  --deep-scan            Executa ambos os testes avançados"
    echo "  --help                 Mostra esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  $0 192.168.1.0/24                           # Detecção básica de loops"
    echo "  $0 192.168.1.0/24 --asymmetric-routing      # + Detecção de roteamento assimétrico"
    echo "  $0 192.168.1.0/24 --mtu-problems           # + Detecção de problemas MTU"
    echo "  $0 192.168.1.0/24 --deep-scan              # Análise completa"
    echo "  $0 192.168.1.0/24 \"token\" \"chat\"          # Sobrescreve configuração interna"
    echo ""
    echo "Funcionalidades:"
    echo "• Detecção de loops de roteamento usando fping"
    echo "• Análise detalhada com traceroute"
    echo "• Detecção de roteamento assimétrico (opcional)"
    echo "• Detecção de problemas de MTU (opcional)"
    echo "• Relatório HTML moderno e interativo"
    echo "• Relatório TXT detalhado"
    echo "• Envio automático para Telegram"
    echo "• Estatísticas e gráficos"
    echo ""
    echo "Configuração do Telegram:"
    echo "• Configure BOT_TOKEN e CHAT_ID diretamente no script (linhas 11-12)"
    echo "• Ou passe como parâmetros para sobrescrever a configuração interna"
    exit 1
}

# Função para enviar mensagem ao Telegram
send_telegram() {
    local message="$1"
    local bot_token="$2"
    local chat_id="$3"
    
    if [[ -n "$bot_token" && -n "$chat_id" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d chat_id="${chat_id}" \
            -d text="${message}" \
            -d parse_mode="HTML" > /dev/null
    fi
}

# Função para enviar arquivo ao Telegram
send_telegram_file() {
    local file_path="$1"
    local caption="$2"
    local bot_token="$3"
    local chat_id="$4"
    
    if [[ -n "$bot_token" && -n "$chat_id" && -f "$file_path" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendDocument" \
            -F chat_id="${chat_id}" \
            -F document=@"${file_path}" \
            -F caption="${caption}" \
            -F parse_mode="HTML" > /dev/null
    fi
}

# Função para validar CIDR
validate_cidr() {
    local cidr="$1"
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${RED}Erro: CIDR inválido. Use o formato IP/MASK (ex: 192.168.1.0/24)${NC}"
        exit 1
    fi
}

# Função para gerar lista de IPs do CIDR
generate_ip_list() {
    local cidr="$1"
    nmap -sL "$cidr" 2>/dev/null | grep "Nmap scan report" | awk '{print $5}' | grep -E '^[0-9]'
}

# Função para detectar roteamento assimétrico
detect_asymmetric_routing() {
    local ip="$1"
    echo -e "${YELLOW}[ASYMMETRIC] Testando roteamento assimétrico para $ip...${NC}"
    
    # Testa com diferentes métodos
    local udp_trace=$(timeout 10 traceroute -n -U -w 2 -m 8 "$ip" 2>/dev/null)
    local tcp_trace=$(timeout 10 traceroute -n -T -w 2 -m 8 "$ip" 2>/dev/null)
    local icmp_trace=$(timeout 10 traceroute -n -I -w 2 -m 8 "$ip" 2>/dev/null)
    
    # Compara as rotas extraindo apenas os IPs dos hops
    local udp_ips=$(echo "$udp_trace" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -8 | sort)
    local tcp_ips=$(echo "$tcp_trace" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -8 | sort)
    local icmp_ips=$(echo "$icmp_trace" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -8 | sort)
    
    local asymmetric_detected=false
    local asymmetric_details=""
    
    # Compara UDP vs TCP
    if [[ -n "$udp_ips" && -n "$tcp_ips" && "$udp_ips" != "$tcp_ips" ]]; then
        asymmetric_detected=true
        asymmetric_details+="UDP vs TCP: Rotas diferentes detectadas\\n"
    fi
    
    # Compara UDP vs ICMP
    if [[ -n "$udp_ips" && -n "$icmp_ips" && "$udp_ips" != "$icmp_ips" ]]; then
        asymmetric_detected=true
        asymmetric_details+="UDP vs ICMP: Rotas diferentes detectadas\\n"
    fi
    
    # Compara TCP vs ICMP
    if [[ -n "$tcp_ips" && -n "$icmp_ips" && "$tcp_ips" != "$icmp_ips" ]]; then
        asymmetric_detected=true
        asymmetric_details+="TCP vs ICMP: Rotas diferentes detectadas\\n"
    fi
    
    if [[ "$asymmetric_detected" == "true" ]]; then
        echo -e "${RED}[ASYMMETRIC] $ip - ROTEAMENTO ASSIMÉTRICO DETECTADO!${NC}"
        echo -e "${YELLOW}Detalhes: $asymmetric_details${NC}"
        return 0
    else
        echo -e "${GREEN}[ASYMMETRIC] $ip - Roteamento consistente${NC}"
        return 1
    fi
}

# Função para detectar problemas de MTU
detect_mtu_problems() {
    local ip="$1"
    echo -e "${YELLOW}[MTU] Testando MTU para $ip...${NC}"
    
    # Testa diferentes tamanhos de MTU (1500, 1400, 1300, 1200, 1000)
    local mtu_sizes=(1500 1400 1300 1200 1000 900 800 700 600 500)
    local working_mtu=""
    local mtu_problem=false
    
    for size in "${mtu_sizes[@]}"; do
        # Ping com tamanho específico e DF (Don't Fragment)
        # Subtrai 28 bytes (20 IP + 8 ICMP)
        local payload_size=$((size - 28))
        
        if ping -c 1 -W 2 -s "$payload_size" -M do "$ip" >/dev/null 2>&1; then
            working_mtu=$size
            break
        fi
    done
    
    if [[ -n "$working_mtu" ]]; then
        if [[ $working_mtu -lt 1500 ]]; then
            mtu_problem=true
            echo -e "${RED}[MTU] $ip - PROBLEMA DE MTU DETECTADO! MTU máximo: ${working_mtu}${NC}"
            return 0
        else
            echo -e "${GREEN}[MTU] $ip - MTU normal (${working_mtu})${NC}"
            return 1
        fi
    else
        echo -e "${RED}[MTU] $ip - PROBLEMA CRÍTICO DE MTU! Nenhum tamanho funcionou${NC}"
        return 0
    fi
}

# Função para criar estrutura de diretórios
setup_temp_dir() {
    mkdir -p "$TEMP_DIR"
    HTML_REPORT_FILE="$TEMP_DIR/loop_report_${REPORT_DATE}.html"
    TXT_REPORT_FILE="$TEMP_DIR/loop_report_${REPORT_DATE}.txt"
}

# Função para gerar relatório HTML
generate_html_report() {
    local cidr="$1"
    local total_ips="$2"
    local ips_ok="$3"
    local ips_loop="$4"
    local loop_rate="$5"
    local scan_duration="$6"
    local test_asymmetric="$7"
    local test_mtu="$8"
    local asymmetric_problems="$9"
    local mtu_problems="${10}"
    shift 10
    local problematic_ips=("$@")
    
    echo -e "${YELLOW}Gerando relatório HTML...${NC}"
    
    # Calcula totais incluindo novos problemas
    local total_problems=$((ips_loop + asymmetric_problems + mtu_problems))
    local total_healthy=$((total_ips - total_problems))
    
    cat > "$HTML_REPORT_FILE" << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Loop Detector Report - $cidr</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
            position: relative;
        }

        .header::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="20" cy="20" r="2" fill="white" opacity="0.1"/><circle cx="80" cy="80" r="2" fill="white" opacity="0.1"/><circle cx="60" cy="30" r="1" fill="white" opacity="0.1"/><circle cx="30" cy="70" r="1" fill="white" opacity="0.1"/></svg>');
        }

        .header h1 {
            font-size: 2.8em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
            position: relative;
            z-index: 1;
        }

        .header .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
            position: relative;
            z-index: 1;
        }

        .test-badges {
            display: flex;
            gap: 10px;
            margin-top: 15px;
            flex-wrap: wrap;
            justify-content: center;
        }

        .badge {
            padding: 5px 12px;
            border-radius: 15px;
            font-size: 0.8em;
            font-weight: bold;
            color: white;
        }

        .badge.enabled {
            background: #28a745;
        }

        .badge.disabled {
            background: #6c757d;
        }

        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 25px;
            padding: 40px;
            background: #f8f9fa;
        }

        .summary-card {
            background: white;
            border-radius: 15px;
            padding: 25px 20px;
            text-align: center;
            box-shadow: 0 10px 20px rgba(0,0,0,0.1);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            border: 1px solid #e9ecef;
            min-height: 180px;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
        }

        .summary-card:hover {
            transform: translateY(-10px);
            box-shadow: 0 20px 40px rgba(0,0,0,0.15);
        }

        .summary-card .icon {
            font-size: 2.8em;
            margin-bottom: 15px;
            display: block;
        }

        .summary-card h3 {
            margin-bottom: 15px;
            font-size: 1.1em;
            color: #495057;
        }

        .summary-card .value {
            font-size: 2em;
            font-weight: bold;
            margin-bottom: 10px;
            word-wrap: break-word;
            word-break: break-all;
            overflow-wrap: break-word;
            line-height: 1.1;
            max-width: 100%;
        }

        .summary-card .value.network-cidr {
            font-size: 1.4em;
            word-spacing: -0.1em;
            letter-spacing: -0.02em;
            line-height: 1.2;
        }

        .summary-card .label {
            color: #6c757d;
            font-size: 0.9em;
        }

        .status-healthy { color: #28a745; }
        .status-warning { color: #ffc107; }
        .status-critical { color: #dc3545; }
        .status-info { color: #17a2b8; }
        .status-mtu { color: #fd7e14; }
        .status-asymmetric { color: #6f42c1; }

        .content {
            padding: 40px;
        }

        .section {
            margin-bottom: 40px;
            background: white;
            border-radius: 15px;
            padding: 30px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
            border: 1px solid #e9ecef;
        }

        .section h2 {
            margin-bottom: 20px;
            color: #495057;
            font-size: 1.8em;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }

        .chart-container {
            position: relative;
            height: 400px;
            margin-bottom: 30px;
        }

        .problem-list {
            list-style: none;
        }

        .problem-item {
            background: #f8f9fa;
            margin-bottom: 20px;
            padding: 25px;
            border-radius: 10px;
            border-left: 5px solid #dc3545;
            transition: background 0.3s ease;
        }

        .problem-item.asymmetric {
            border-left-color: #6f42c1;
        }

        .problem-item.mtu {
            border-left-color: #fd7e14;
        }

        .problem-item:hover {
            background: #e9ecef;
        }

        .problem-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }

        .problem-ip {
            font-size: 1.2em;
            font-weight: bold;
            color: #dc3545;
        }

        .problem-type {
            background: #dc3545;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
        }

        .problem-type.asymmetric {
            background: #6f42c1;
        }

        .problem-type.mtu {
            background: #fd7e14;
        }

        .traceroute {
            background: #343a40;
            color: #00ff00;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            line-height: 1.4;
            overflow-x: auto;
            margin-top: 15px;
        }

        .recommendations {
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            padding: 30px;
            border-radius: 15px;
            margin-top: 30px;
        }

        .recommendations h3 {
            margin-bottom: 20px;
            font-size: 1.5em;
        }

        .recommendations ul {
            list-style: none;
        }

        .recommendations li {
            margin-bottom: 10px;
            padding-left: 25px;
            position: relative;
        }

        .recommendations li::before {
            content: '✓';
            position: absolute;
            left: 0;
            font-weight: bold;
            color: #ffffff;
        }

        .footer {
            background: #343a40;
            color: white;
            text-align: center;
            padding: 30px;
            font-size: 0.9em;
        }

        .footer .logo {
            font-size: 1.5em;
            margin-bottom: 10px;
        }

        .healthy-network {
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            text-align: center;
            padding: 50px;
            border-radius: 15px;
            margin: 30px 0;
        }

        .healthy-network .icon {
            font-size: 5em;
            margin-bottom: 20px;
        }

        .healthy-network h2 {
            font-size: 2.5em;
            margin-bottom: 15px;
            border: none;
            color: white;
        }

        @media (max-width: 768px) {
            .summary-grid {
                grid-template-columns: 1fr;
                padding: 20px;
            }
            
            .content {
                padding: 20px;
            }
            
            .section {
                padding: 20px;
            }
            
            .header {
                padding: 30px 20px;
            }
            
            .header h1 {
                font-size: 2em;
            }

            .problem-header {
                flex-direction: column;
                align-items: flex-start;
                gap: 10px;
            }

            .summary-card .value {
                font-size: 1.8em;
            }

            .summary-card .value.network-cidr {
                font-size: 1.2em;
            }
        }

        .pulse {
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.05); }
            100% { transform: scale(1); }
        }

        .fade-in {
            animation: fadeIn 1s ease-in;
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
    </style>
</head>
<body>
    <div class="container fade-in">
        <div class="header">
            <h1>🔍 Loop Detector Report</h1>
            <div class="subtitle">Relatório de Análise de Rede Avançado</div>
            <div class="test-badges">
                <span class="badge enabled">Loops</span>
                <span class="badge $([ "$test_asymmetric" == "true" ] && echo "enabled" || echo "disabled")">Roteamento Assimétrico</span>
                <span class="badge $([ "$test_mtu" == "true" ] && echo "enabled" || echo "disabled")">MTU Problems</span>
            </div>
        </div>

        <div class="summary-grid">
            <div class="summary-card pulse">
                <span class="icon">🌐</span>
                <h3>Rede Analisada</h3>
                <div class="value network-cidr status-info">$cidr</div>
                <div class="label">Bloco de rede</div>
            </div>
            <div class="summary-card">
                <span class="icon">📊</span>
                <h3>Total de IPs</h3>
                <div class="value status-info">$total_ips</div>
                <div class="label">Endereços testados</div>
            </div>
            <div class="summary-card">
                <span class="icon">✅</span>
                <h3>IPs Saudáveis</h3>
                <div class="value status-healthy">$total_healthy</div>
                <div class="label">$(echo "scale=1; $total_healthy * 100 / $total_ips" | bc -l 2>/dev/null || echo "0")% da rede</div>
            </div>
            <div class="summary-card">
                <span class="icon">⚠️</span>
                <h3>Loops Detectados</h3>
                <div class="value status-critical">$ips_loop</div>
                <div class="label">${loop_rate}% da rede</div>
            </div>
EOF

    # Adiciona cards para funcionalidades avançadas se habilitadas
    if [[ "$test_asymmetric" == "true" ]]; then
        cat >> "$HTML_REPORT_FILE" << EOF
            <div class="summary-card">
                <span class="icon">🔄</span>
                <h3>Roteamento Assimétrico</h3>
                <div class="value status-asymmetric">$asymmetric_problems</div>
                <div class="label">IPs detectados</div>
            </div>
EOF
    fi

    if [[ "$test_mtu" == "true" ]]; then
        cat >> "$HTML_REPORT_FILE" << EOF
            <div class="summary-card">
                <span class="icon">📏</span>
                <h3>Problemas MTU</h3>
                <div class="value status-mtu">$mtu_problems</div>
                <div class="label">IPs afetados</div>
            </div>
EOF
    fi

    cat >> "$HTML_REPORT_FILE" << EOF
        </div>

        <div class="content">
            <div class="section">
                <h2>📈 Análise Visual</h2>
                <div class="chart-container">
                    <canvas id="statusChart"></canvas>
                </div>
            </div>

EOF

    # Se há problemas, adiciona seção de problemas
    if [[ $total_problems -gt 0 ]]; then
        cat >> "$HTML_REPORT_FILE" << EOF
            <div class="section">
                <h2>🚨 Problemas Detectados</h2>
                <ul class="problem-list">
EOF

        # Adiciona cada IP problemático (lê do arquivo de resultados)
        if [[ -f "$TEMP_DIR/all_problems.tmp" ]]; then
            while IFS='|' read -r ip problem_type details; do
                if [[ -n "$ip" ]]; then
                    local problem_class=""
                    local problem_icon="⚠️"
                    local problem_label="$problem_type"
                    
                    case "$problem_type" in
                        "loop")
                            problem_class="loop"
                            problem_icon="🔄"
                            problem_label="Loop de Roteamento"
                            ;;
                        "asymmetric")
                            problem_class="asymmetric"
                            problem_icon="🔄"
                            problem_label="Roteamento Assimétrico"
                            ;;
                        "mtu")
                            problem_class="mtu"
                            problem_icon="📏"
                            problem_label="Problema MTU"
                            ;;
                    esac
                    
                    cat >> "$HTML_REPORT_FILE" << EOF
                    <li class="problem-item $problem_class">
                        <div class="problem-header">
                            <span class="problem-ip">$problem_icon $ip</span>
                            <span class="problem-type $problem_class">$problem_label</span>
                        </div>
                        <div><strong>Status:</strong> REQUER ATENÇÃO - Verificar configuração</div>
                        <div class="traceroute">
<strong>Detalhes do Problema:</strong>
$details
                        </div>
                    </li>
EOF
                fi
            done < "$TEMP_DIR/all_problems.tmp"
        fi

        cat >> "$HTML_REPORT_FILE" << EOF
                </ul>
            </div>

            <div class="recommendations">
                <h3>💡 Recomendações Técnicas</h3>
                <ul>
                    <li>Verificar configuração de rotas nos equipamentos afetados</li>
                    <li>Analisar tabelas de roteamento para detectar rotas circulares</li>
                    <li>Verificar configuração de protocolos de roteamento (OSPF/BGP)</li>
                    <li>Implementar filtragem de rotas adequada</li>
                    <li>Para problemas de MTU: verificar configuração de interfaces</li>
                    <li>Para roteamento assimétrico: analisar políticas de roteamento</li>
                    <li>Configurar métricas de rota para evitar loops</li>
                    <li>Monitorar continuamente a infraestrutura de rede</li>
                    <li>Implementar redundância com STP/RSTP se aplicável</li>
                    <li>Revisar topologia física da rede</li>
                </ul>
            </div>
EOF
    else
        # Rede saudável
        cat >> "$HTML_REPORT_FILE" << EOF
            <div class="healthy-network">
                <div class="icon">🎉</div>
                <h2>Rede Totalmente Saudável!</h2>
                <p style="font-size: 1.2em; margin-bottom: 20px;">
                    Parabéns! Nenhum problema foi detectado na rede <strong>$cidr</strong>
                </p>
                <p style="font-size: 1.1em;">
                    ✅ Todos os $total_ips endereços IP testados estão funcionando corretamente<br>
                    ✅ Nenhum loop de roteamento detectado<br>
EOF

        if [[ "$test_asymmetric" == "true" ]]; then
            cat >> "$HTML_REPORT_FILE" << EOF
                    ✅ Nenhum problema de roteamento assimétrico detectado<br>
EOF
        fi

        if [[ "$test_mtu" == "true" ]]; then
            cat >> "$HTML_REPORT_FILE" << EOF
                    ✅ Nenhum problema de MTU detectado<br>
EOF
        fi

        cat >> "$HTML_REPORT_FILE" << EOF
                    ✅ A infraestrutura de rede está operacional e estável<br>
                    ✅ Tempo de varredura: ${scan_duration}s
                </p>
            </div>
EOF
    fi

    # Finaliza o HTML
    cat >> "$HTML_REPORT_FILE" << EOF
            <div class="section">
                <h2>📋 Informações da Varredura</h2>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px;">
                    <div>
                        <strong>Data/Hora:</strong><br>
                        $(date +'%d/%m/%Y %H:%M:%S')
                    </div>
                    <div>
                        <strong>Duração:</strong><br>
                        ${scan_duration} segundos
                    </div>
                    <div>
                        <strong>Host:</strong><br>
                        $(hostname)
                    </div>
                    <div>
                        <strong>Usuário:</strong><br>
                        $(whoami)
                    </div>
                    <div>
                        <strong>Versão:</strong><br>
                        Loop Detector v$SCRIPT_VERSION
                    </div>
                    <div>
                        <strong>Testes:</strong><br>
                        fping, traceroute$([ "$test_asymmetric" == "true" ] && echo ", asymmetric")$([ "$test_mtu" == "true" ] && echo ", mtu")
                    </div>
                </div>
            </div>
        </div>

        <div class="footer">
            <div class="logo">🔍 Loop Detector Enhanced</div>
            <div>Versão $SCRIPT_VERSION - Análise avançada de redes</div>
            <div style="margin-top: 10px; opacity: 0.8;">
                Relatório gerado automaticamente em $(date +'%d/%m/%Y às %H:%M:%S')
            </div>
        </div>
    </div>

    <script>
        // Configuração do gráfico
        const ctx = document.getElementById('statusChart').getContext('2d');
        
        // Dados para o gráfico
        const chartLabels = ['IPs Saudáveis', 'Loops'];
        const chartData = [$total_healthy, $ips_loop];
        const chartColors = ['#28a745', '#dc3545'];
        
        $([ "$test_asymmetric" == "true" ] && echo "chartLabels.push('Roteamento Assimétrico'); chartData.push($asymmetric_problems); chartColors.push('#6f42c1');")
        $([ "$test_mtu" == "true" ] && echo "chartLabels.push('Problemas MTU'); chartData.push($mtu_problems); chartColors.push('#fd7e14');")

        const chart = new Chart(ctx, {
            type: 'doughnut',
            data: {
                labels: chartLabels,
                datasets: [{
                    data: chartData,
                    backgroundColor: chartColors,
                    borderColor: Array(chartColors.length).fill('#ffffff'),
                    borderWidth: 3
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 20,
                            font: {
                                size: 14
                            }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                const label = context.label || '';
                                const value = context.parsed;
                                const total = $total_ips;
                                const percentage = ((value / total) * 100).toFixed(1);
                                return label + ': ' + value + ' (' + percentage + '%)';
                            }
                        }
                    }
                },
                cutout: '60%',
                animation: {
                    animateRotate: true,
                    duration: 2000
                }
            }
        });

        // Animações na página
        document.addEventListener('DOMContentLoaded', function() {
            // Anima contadores (exceto CIDR)
            const counters = document.querySelectorAll('.value');
            counters.forEach(counter => {
                if (!counter.classList.contains('network-cidr')) {
                    const target = parseInt(counter.textContent.replace(/[^0-9]/g, ''));
                    if (!isNaN(target) && target > 0) {
                        let current = 0;
                        const increment = target / 50;
                        const timer = setInterval(() => {
                            current += increment;
                            if (current >= target) {
                                counter.textContent = counter.textContent.replace(/[0-9]+/, target);
                                clearInterval(timer);
                            } else {
                                counter.textContent = counter.textContent.replace(/[0-9]+/, Math.floor(current));
                            }
                        }, 30);
                    }
                }
            });
        });
    </script>
</body>
</html>
EOF

    echo -e "${GREEN}✅ Relatório HTML gerado: $HTML_REPORT_FILE${NC}"
}

# Função para gerar relatório TXT
generate_txt_report() {
    local cidr="$1"
    local total_ips="$2"
    local ips_ok="$3"
    local ips_loop="$4"
    local loop_rate="$5"
    local scan_duration="$6"
    local test_asymmetric="$7"
    local test_mtu="$8"
    local asymmetric_problems="$9"
    local mtu_problems="${10}"
    shift 10
    local problematic_ips=("$@")
    
    echo -e "${YELLOW}Gerando relatório TXT...${NC}"
    
    local total_problems=$((ips_loop + asymmetric_problems + mtu_problems))
    
    cat > "$TXT_REPORT_FILE" << EOF
============================================
    RELATÓRIO DE ANÁLISE DE REDE
============================================

Data/Hora: $(date +'%d/%m/%Y %H:%M:%S')
Rede Analisada: $cidr
Host: $(hostname)
Usuário: $(whoami)
Duração da Varredura: ${scan_duration}s
Versão: Loop Detector v$SCRIPT_VERSION

TESTES EXECUTADOS:
=================
• Detecção de loops de roteamento: ✓
$([ "$test_asymmetric" == "true" ] && echo "• Detecção de roteamento assimétrico: ✓" || echo "• Detecção de roteamento assimétrico: -")
$([ "$test_mtu" == "true" ] && echo "• Detecção de problemas MTU: ✓" || echo "• Detecção de problemas MTU: -")

RESUMO EXECUTIVO:
================
• Total de IPs testados: $total_ips
• IPs funcionando corretamente: $ips_ok
• Loops de roteamento detectados: $ips_loop
$([ "$test_asymmetric" == "true" ] && echo "• Problemas de roteamento assimétrico: $asymmetric_problems")
$([ "$test_mtu" == "true" ] && echo "• Problemas de MTU detectados: $mtu_problems")
• Taxa de loops: ${loop_rate}%
• Total de problemas: $total_problems

EOF

    if [[ $total_problems -gt 0 ]]; then
        cat >> "$TXT_REPORT_FILE" << EOF
DETALHES DOS PROBLEMAS ENCONTRADOS:
=================================

EOF
        
        # Processa o arquivo de problemas consolidado
        if [[ -f "$TEMP_DIR/all_problems.tmp" ]]; then
            local counter=1
            while IFS='|' read -r ip problem_type details; do
                if [[ -n "$ip" ]]; then
                    local problem_title=""
                    local problem_desc=""
                    
                    case "$problem_type" in
                        "loop")
                            problem_title="LOOP DE ROTEAMENTO"
                            problem_desc="TTL Expired - Loop detectado na rota"
                            ;;
                        "asymmetric")
                            problem_title="ROTEAMENTO ASSIMÉTRICO"
                            problem_desc="Rotas diferentes para protocolos UDP/TCP/ICMP"
                            ;;
                        "mtu")
                            problem_title="PROBLEMA DE MTU"
                            problem_desc="MTU reduzido ou fragmentação bloqueada"
                            ;;
                    esac
                    
                    cat >> "$TXT_REPORT_FILE" << EOF
[$counter] IP: $ip
    Tipo: $problem_title
    Descrição: $problem_desc
    Diagnóstico:
$(echo "$details" | tr '|' '\n' | sed 's/^/    /')
    
    Status: REQUER ATENÇÃO - Verificar configuração
    Prioridade: $([ "$problem_type" == "loop" ] && echo "ALTA" || echo "MÉDIA")

EOF
                    ((counter++))
                fi
            done < "$TEMP_DIR/all_problems.tmp"
        fi
        
        cat >> "$TXT_REPORT_FILE" << EOF
RECOMENDAÇÕES TÉCNICAS:
======================
EOF

        if [[ $ips_loop -gt 0 ]]; then
            cat >> "$TXT_REPORT_FILE" << EOF

Para Loops de Roteamento:
------------------------
1. Verificar configuração de rotas nos equipamentos afetados
2. Analisar tabelas de roteamento para detectar rotas circulares
3. Verificar configuração de protocolos de roteamento (OSPF/BGP)
4. Implementar filtragem de rotas adequada
5. Configurar métricas de rota para evitar loops
6. Revisar configuração de VLANs e STP
EOF
        fi

        if [[ "$test_asymmetric" == "true" && $asymmetric_problems -gt 0 ]]; then
            cat >> "$TXT_REPORT_FILE" << EOF

Para Roteamento Assimétrico:
----------------------------
1. Verificar políticas de roteamento em firewalls
2. Analisar configuração de load balancers
3. Verificar configuração de BGP e múltiplos paths
4. Revisar configuração de routing policies
5. Implementar source-based routing se necessário
EOF
        fi

        if [[ "$test_mtu" == "true" && $mtu_problems -gt 0 ]]; then
            cat >> "$TXT_REPORT_FILE" << EOF

Para Problemas de MTU:
---------------------
1. Verificar configuração de MTU nas interfaces
2. Analisar configuração de tunnels (GRE, VPN)
3. Verificar MSS clamping em firewalls
4. Revisar configuração de VLANs e encapsulamento
5. Implementar path MTU discovery adequadamente
EOF
        fi

        cat >> "$TXT_REPORT_FILE" << EOF

Recomendações Gerais:
--------------------
6. Monitorar continuamente a infraestrutura de rede
7. Implementar redundância com protocolos adequados
8. Revisar topologia física da rede
9. Documentar mudanças na configuração
10. Realizar testes regulares de conectividade

EOF
    else
        cat >> "$TXT_REPORT_FILE" << EOF
RESULTADO: REDE TOTALMENTE SAUDÁVEL
==================================

✅ Nenhum problema foi detectado na rede $cidr
✅ Todos os $total_ips IPs testados estão funcionando corretamente
✅ Nenhum loop de roteamento detectado
$([ "$test_asymmetric" == "true" ] && echo "✅ Nenhum problema de roteamento assimétrico detectado")
$([ "$test_mtu" == "true" ] && echo "✅ Nenhum problema de MTU detectado")
✅ A infraestrutura de rede está operacional e estável
✅ Tempo de varredura otimizado: ${scan_duration}s

MANUTENÇÃO PREVENTIVA:
=====================
• Continue monitorando a rede regularmente
• Mantenha documentação de configuração atualizada
• Realize backups periódicos das configurações
• Monitore crescimento do tráfego e capacidade

EOF
    fi

    cat >> "$TXT_REPORT_FILE" << EOF
============================================
Relatório gerado pelo Loop Detector v$SCRIPT_VERSION
Ferramentas utilizadas: fping, traceroute$([ "$test_asymmetric" == "true" ] && echo ", multi-protocol trace")$([ "$test_mtu" == "true" ] && echo ", MTU discovery")
============================================
EOF

    echo -e "${GREEN}✅ Relatório TXT gerado: $TXT_REPORT_FILE${NC}"
}

# Função principal de detecção
run_loop_detection() {
    local cidr="$1"
    local bot_token="$2"
    local chat_id="$3"
    local test_asymmetric="$4"
    local test_mtu="$5"
    
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        LOOP DETECTOR ENHANCED v$SCRIPT_VERSION        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] Iniciando varredura em $cidr${NC}"
    
    # Mostra testes habilitados
    echo -e "${CYAN}Testes habilitados:${NC}"
    echo -e "${GREEN}  ✅ Detecção de loops de roteamento${NC}"
    if [[ "$test_asymmetric" == "true" ]]; then
        echo -e "${GREEN}  ✅ Detecção de roteamento assimétrico${NC}"
    fi
    if [[ "$test_mtu" == "true" ]]; then
        echo -e "${GREEN}  ✅ Detecção de problemas de MTU${NC}"
    fi
    echo ""

    # Verifica dependências
    echo -e "${YELLOW}Verificando dependências...${NC}"
    local missing_deps=()
    
    for cmd in fping nmap traceroute curl bc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Dependências em falta: ${missing_deps[*]}${NC}"
        echo "Instale com: sudo apt install ${missing_deps[*]}"
        exit 1
    fi
    echo -e "${GREEN}✅ Todas as dependências estão instaladas${NC}"
    echo ""

    # Gera lista de IPs
    echo -e "${YELLOW}Gerando lista de IPs para varredura...${NC}"
    local ip_list
    ip_list=$(generate_ip_list "$cidr")
    
    if [[ -z "$ip_list" ]]; then
        echo -e "${RED}Erro: Não foi possível gerar lista de IPs para $cidr${NC}"
        exit 1
    fi

    local total_ips
    total_ips=$(echo "$ip_list" | wc -l)
    echo -e "${GREEN}✅ $total_ips IPs serão testados${NC}"
    echo ""

    # Variáveis para contadores
    local ips_ok=0
    local ips_loop=0
    local asymmetric_problems=0
    local mtu_problems=0
    local problematic_ips=()
    local temp_loops_file="$TEMP_DIR/loops.tmp"
    local temp_asymmetric_file="$TEMP_DIR/asymmetric.tmp"
    local temp_mtu_file="$TEMP_DIR/mtu.tmp"
    local all_problems_file="$TEMP_DIR/all_problems.tmp"

    # Limpa arquivos temporários
    > "$temp_loops_file"
    > "$temp_asymmetric_file" 
    > "$temp_mtu_file"
    > "$all_problems_file"

    # Executa detecção básica de loops
    echo -e "${CYAN}🔍 Iniciando detecção de loops...${NC}"
    echo ""
    
    local current=0
    echo "$ip_list" | while read -r ip; do
        if [[ -n "$ip" ]]; then
            ((current++))
            local progress=$((current * 100 / total_ips))
            
            echo -ne "\r${YELLOW}Progresso: [$progress%] Testando $ip...${NC}"
            
            # Teste de loop com fping
            local result
            result=$(fping -c 1 -t 1000 -T 3 "$ip" 2>&1)
            
            if echo "$result" | grep -q "TTL expired\|Time exceeded\|ICMP Time Exceeded"; then
                echo -e "\n${RED}[LOOP] $ip - LOOP DETECTADO!${NC}"
                echo "$ip" >> "$temp_loops_file"
                
                # Adiciona ao arquivo de problemas consolidado
                local trace_details=$(timeout 10 traceroute -m 10 "$ip" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
                echo "$ip|loop|$trace_details" >> "$all_problems_file"
            else
                echo -ne " ${GREEN}OK${NC}"
            fi
        fi
    done
    
    echo ""
    echo ""

    # Testes avançados (apenas em alguns IPs para economizar tempo)
    local sample_ips
    sample_ips=$(echo "$ip_list" | head -20)  # Testa apenas os primeiros 20 IPs
    
    if [[ "$test_asymmetric" == "true" ]]; then
        echo -e "${PURPLE}🔄 Iniciando detecção de roteamento assimétrico...${NC}"
        for ip in $sample_ips; do
            if [[ -n "$ip" ]]; then
                if detect_asymmetric_routing "$ip"; then
                    echo "$ip" >> "$temp_asymmetric_file"
                    echo "$ip|asymmetric|Rotas diferentes detectadas com múltiplos protocolos (UDP/TCP/ICMP)" >> "$all_problems_file"
                fi
            fi
        done
        echo ""
    fi

    if [[ "$test_mtu" == "true" ]]; then
        echo -e "${CYAN}📏 Iniciando detecção de problemas de MTU...${NC}"
        for ip in $sample_ips; do
            if [[ -n "$ip" ]]; then
                if detect_mtu_problems "$ip"; then
                    echo "$ip" >> "$temp_mtu_file"
                    local mtu_details=$(ping -c 1 -W 2 -s 1472 -M do "$ip" 2>&1 | grep -o "MTU.*" || echo "MTU reduzido detectado")
                    echo "$ip|mtu|$mtu_details" >> "$all_problems_file"
                fi
            fi
        done
        echo ""
    fi

    # Processa resultados
    if [[ -f "$temp_loops_file" ]]; then
        ips_loop=$(wc -l < "$temp_loops_file")
        mapfile -t problematic_ips < "$temp_loops_file"
    fi

    if [[ -f "$temp_asymmetric_file" ]]; then
        asymmetric_problems=$(wc -l < "$temp_asymmetric_file")
    fi

    if [[ -f "$temp_mtu_file" ]]; then
        mtu_problems=$(wc -l < "$temp_mtu_file")
    fi

    local total_problems=$((ips_loop + asymmetric_problems + mtu_problems))
    ips_ok=$((total_ips - ips_loop))  # Apenas considera loops para IPs "OK"

    # Calcula taxa de loops e duração
    local loop_rate
    if [[ $total_ips -gt 0 ]]; then
        loop_rate=$(echo "scale=2; $ips_loop * 100 / $total_ips" | bc -l 2>/dev/null || echo "0.00")
    else
        loop_rate="0.00"
    fi

    local end_time
    end_time=$(date +%s)
    local scan_duration=$((end_time - START_TIME))

    # Mostra resumo
    echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                 RESUMO FINAL                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}📊 Total de IPs testados: $total_ips${NC}"
    echo -e "${GREEN}✅ IPs OK: $ips_ok${NC}"
    echo -e "${RED}⚠️  Loops detectados: $ips_loop${NC}"
    if [[ "$test_asymmetric" == "true" ]]; then
        echo -e "${PURPLE}🔄 Roteamento assimétrico: $asymmetric_problems${NC}"
    fi
    if [[ "$test_mtu" == "true" ]]; then
        echo -e "${CYAN}📏 Problemas MTU: $mtu_problems${NC}"
    fi
    echo -e "${YELLOW}📈 Taxa de loops: ${loop_rate}%${NC}"
    echo -e "${CYAN}⏱️  Duração: ${scan_duration}s${NC}"
    echo ""

    # Mostra problemas detectados
    if [[ $total_problems -gt 0 ]]; then
        echo -e "${RED}🚨 Problemas detectados:${NC}"
        if [[ $ips_loop -gt 0 ]]; then
            echo -e "${RED}   Loops (${ips_loop}):${NC}"
            for ip in "${problematic_ips[@]}"; do
                if [[ -n "$ip" ]]; then
                    echo -e "${RED}     • $ip${NC}"
                fi
            done
        fi
        
        if [[ "$test_asymmetric" == "true" && $asymmetric_problems -gt 0 ]]; then
            echo -e "${PURPLE}   Roteamento Assimétrico (${asymmetric_problems}):${NC}"
            while read -r ip; do
                echo -e "${PURPLE}     • $ip${NC}"
            done < "$temp_asymmetric_file"
        fi
        
        if [[ "$test_mtu" == "true" && $mtu_problems -gt 0 ]]; then
            echo -e "${CYAN}   Problemas MTU (${mtu_problems}):${NC}"
            while read -r ip; do
                echo -e "${CYAN}     • $ip${NC}"
            done < "$temp_mtu_file"
        fi
        echo ""
    fi

    # Gera relatórios
    if [[ "$ENABLE_HTML_REPORT" == "true" ]]; then
        generate_html_report "$cidr" "$total_ips" "$ips_ok" "$ips_loop" "$loop_rate" "$scan_duration" "$test_asymmetric" "$test_mtu" "$asymmetric_problems" "$mtu_problems" "${problematic_ips[@]}"
    fi
    
    generate_txt_report "$cidr" "$total_ips" "$ips_ok" "$ips_loop" "$loop_rate" "$scan_duration" "$test_asymmetric" "$test_mtu" "$asymmetric_problems" "$mtu_problems" "${problematic_ips[@]}"

    # Envia para Telegram
    if [[ -n "$bot_token" && -n "$chat_id" && "$ENABLE_TELEGRAM" == "true" ]]; then
        echo -e "${YELLOW}📱 Enviando relatórios para Telegram...${NC}"
        
        # Prepara mensagem resumida
        local telegram_message="🔍 <b>Loop Detector Enhanced v$SCRIPT_VERSION</b>%0A%0A"
        telegram_message+="📊 <b>Resumo da Varredura:</b>%0A"
        telegram_message+="• Rede: <code>$cidr</code>%0A"
        telegram_message+="• Total testados: $total_ips IPs%0A"
        telegram_message+="• IPs OK: $ips_ok%0A"
        telegram_message+="• Loops detectados: $ips_loop%0A"
        
        if [[ "$test_asymmetric" == "true" ]]; then
            telegram_message+="• Roteamento assimétrico: $asymmetric_problems%0A"
        fi
        
        if [[ "$test_mtu" == "true" ]]; then
            telegram_message+="• Problemas MTU: $mtu_problems%0A"
        fi
        
        telegram_message+="• Taxa de loops: ${loop_rate}%%0A"
        telegram_message+="• Duração: ${scan_duration}s%0A%0A"
        
        if [[ $total_problems -gt 0 ]]; then
            telegram_message+="⚠️ <b>Problemas encontrados:</b>%0A"
            local count=0
            
            # Lista alguns problemas de cada tipo
            if [[ $ips_loop -gt 0 ]]; then
                for ip in "${problematic_ips[@]}"; do
                    if [[ -n "$ip" && $count -lt 4 ]]; then
                        telegram_message+="🔄 <code>$ip</code> (Loop)%0A"
                        ((count++))
                    fi
                done
            fi
            
            if [[ "$test_asymmetric" == "true" && $asymmetric_problems -gt 0 ]]; then
                while read -r ip && [[ $count -lt 6 ]]; do
                    telegram_message+="↔️ <code>$ip</code> (Assimétrico)%0A"
                    ((count++))
                done < "$temp_asymmetric_file"
            fi
            
            if [[ "$test_mtu" == "true" && $mtu_problems -gt 0 ]]; then
                while read -r ip && [[ $count -lt 8 ]]; do
                    telegram_message+="📏 <code>$ip</code> (MTU)%0A"
                    ((count++))
                done < "$temp_mtu_file"
            fi
            
            if [[ $total_problems -gt 8 ]]; then
                telegram_message+="• ... e mais $((total_problems - 8)) problemas%0A"
            fi
            
            telegram_message+="%0A📎 <b>Relatórios detalhados em anexo</b>"
        else
            telegram_message+="✅ <b>Rede totalmente saudável!</b>%0A"
            telegram_message+="🎉 <b>Nenhum problema detectado</b>"
        fi
        
        telegram_message+="%0A⏰ $(date +'%d/%m/%Y %H:%M:%S')"
        
        # Envia mensagem
        send_telegram "$telegram_message" "$bot_token" "$chat_id"
        
        # Envia arquivo TXT
        local txt_caption="📋 Relatório TXT detalhado - $cidr"
        send_telegram_file "$TXT_REPORT_FILE" "$txt_caption" "$bot_token" "$chat_id"
        
        # Envia arquivo HTML se habilitado
        if [[ "$ENABLE_HTML_REPORT" == "true" && -f "$HTML_REPORT_FILE" ]]; then
            local html_caption="🌐 Relatório HTML interativo - $cidr"
            send_telegram_file "$HTML_REPORT_FILE" "$html_caption" "$bot_token" "$chat_id"
        fi
        
        echo -e "${GREEN}✅ Relatórios enviados para Telegram!${NC}"
    fi

    # Informações finais
    echo -e "${CYAN}📁 Arquivos gerados:${NC}"
    if [[ -f "$TXT_REPORT_FILE" ]]; then
        echo -e "${GREEN}   • Relatório TXT: $TXT_REPORT_FILE${NC}"
    fi
    if [[ -f "$HTML_REPORT_FILE" ]]; then
        echo -e "${GREEN}   • Relatório HTML: $HTML_REPORT_FILE${NC}"
        echo -e "${YELLOW}   💡 Abra o arquivo HTML em um navegador para visualizar${NC}"
    fi
    echo ""

    # Limpeza
    rm -f "$temp_loops_file" "$temp_asymmetric_file" "$temp_mtu_file" 2>/dev/null

    echo -e "${GREEN}🎉 Varredura concluída com sucesso!${NC}"
    echo ""

    # Define código de saída
    if [[ $total_problems -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# ==================== EXECUÇÃO PRINCIPAL ====================

# Verifica parâmetros
if [[ $# -lt 1 ]]; then
    show_help
fi

# Processa parâmetros
CIDR=""
TEST_ASYMMETRIC=false
TEST_MTU=false

# Parse dos argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --asymmetric-routing)
            TEST_ASYMMETRIC=true
            shift
            ;;
        --mtu-problems)
            TEST_MTU=true
            shift
            ;;
        --deep-scan)
            TEST_ASYMMETRIC=true
            TEST_MTU=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            if [[ -z "$CIDR" ]]; then
                CIDR="$1"
            elif [[ "$BOT_TOKEN" == "SEU_BOT_TOKEN_AQUI" ]]; then
                BOT_TOKEN="$1"
            elif [[ "$CHAT_ID" == "SEU_CHAT_ID_AQUI" ]]; then
                CHAT_ID="$1"
            fi
            shift
            ;;
    esac
done

# Verifica se CIDR foi fornecido
if [[ -z "$CIDR" ]]; then
    echo -e "${RED}Erro: CIDR é obrigatório${NC}"
    show_help
fi

# Verifica se as configurações do Telegram estão válidas
if [[ "$ENABLE_TELEGRAM" == "true" ]]; then
    if [[ "$BOT_TOKEN" == "SEU_BOT_TOKEN_AQUI" || "$CHAT_ID" == "SEU_CHAT_ID_AQUI" ]]; then
        echo -e "${YELLOW}⚠️  Configurações do Telegram não definidas${NC}"
        echo "Configure BOT_TOKEN e CHAT_ID no script ou passe como parâmetros"
        echo "Executando sem notificações do Telegram..."
        BOT_TOKEN=""
        CHAT_ID=""
        echo ""
    fi
else
    BOT_TOKEN=""
    CHAT_ID=""
fi

# Valida CIDR
validate_cidr "$CIDR"

# Configura diretório temporário
setup_temp_dir

# Executa detecção
run_loop_detection "$CIDR" "$BOT_TOKEN" "$CHAT_ID" "$TEST_ASYMMETRIC" "$TEST_MTU"
