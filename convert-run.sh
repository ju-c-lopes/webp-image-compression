#!/bin/bash
# Script de conversão de imagens para WebP com controle de tamanho máximo por imagem
# e geração de hashes de integridade das imagens originais.

# Faz o shell “falhar rápido”:
# -e  → para na primeira linha que retornar erro
# -u  → erro se usar variável não definida
# -o pipefail → se um comando de um pipeline falhar, o pipeline inteiro é considerado falha
set -euo pipefail

# Qualidade inicial padrão do cwebp (-q).
# Pode ser sobrescrita pela variável de ambiente COMPRESSION_LEVEL
# ou pelo primeiro argumento da linha de comando.
compression_level=${COMPRESSION_LEVEL:-80}
if [ -n "${1:-}" ]; then
    compression_level=$1
fi

# Parâmetros de “inteligência” da compressão:
# - MAX_SIZE_KB   → alvo máximo de tamanho por imagem (em KB)
# - MIN_QUALITY   → qualidade mínima (-q) aceitável
# - QUALITY_STEP  → de quanto em quanto vamos reduzir a qualidade a cada tentativa
# - RESORT_TO_SIZE → se true, usa -size como fallback para forçar o alvo em bytes
# - CWEBP_EXTRA_FLAGS → flags extras do cwebp para melhorar compressão sem sacrificar tanto a qualidade visual
MAX_SIZE_KB=${MAX_SIZE_KB:-100}
MIN_QUALITY=${MIN_QUALITY:-50}
QUALITY_STEP=${QUALITY_STEP:-5}
RESORT_TO_SIZE=${RESORT_TO_SIZE:-true}
CWEBP_EXTRA_FLAGS=${CWEBP_EXTRA_FLAGS:-"-m 6 -pass 10 -af -sns 50 -f 70"}

# Converte o alvo de KB para bytes, pra compararmos com stat -c%s
TARGET_BYTES=$((MAX_SIZE_KB * 1024))

# Converte a string de flags extras do cwebp em um array,
# para podermos passar como "${CWEBP_EXTRA_ARGS[@]}"
declare -a CWEBP_EXTRA_ARGS=()
if [ -n "${CWEBP_EXTRA_FLAGS// /}" ]; then
    # shellcheck disable=SC2206 → ok usar “split por espaços” aqui
    CWEBP_EXTRA_ARGS=($CWEBP_EXTRA_FLAGS)
fi

# Acumuladores de tamanho total original e otimizado (em bytes)
total=0
optimized=0

# Lista de imagens que ainda ficaram acima do limite ou falharam
declare -a oversized_images=()

echo "🎯 Target max size: ${MAX_SIZE_KB} KB | floor quality: ${MIN_QUALITY}"

DIR="${DIR:-$PWD}"
URL_LIST_FILE="$DIR/image-urls.txt"
BACKUP_DIR="$DIR/images-backup"

# Se existir um arquivo com lista de URLs, faz o download das imagens
if [ -f "$URL_LIST_FILE" ]; then
    echo "📥 Downloading images from URL list: $URL_LIST_FILE"
    mkdir -p "$BACKUP_DIR"

    # Lê cada linha do arquivo como uma URL
    while IFS= read -r url; do
        # ignora linhas vazias
        [ -z "$url" ] && continue

        echo "⬇️  Downloading $url"
        # -q  → silencioso
        # -P  → diretório de destino
        wget -q -P "$BACKUP_DIR" "$url" || echo "⚠️ Failed to download: $url"
    done < "$URL_LIST_FILE"

    echo "✅ Finished downloading images to $BACKUP_DIR"
else
    echo "ℹ️ No URL list found at $URL_LIST_FILE (skipping URL download step)."
fi
unset URL_LIST_FILE BACKUP_DIR

# Ajusta permissão no arquivo de hashes original, se existir
if [ -e "$PWD/task-dep/original-hashes.json" ]; then
    chmod 777 "$PWD/task-dep/original-hashes.json"
fi

echo "🔒 Generating integrity hashes..."
# Bloco Python embutido: gera hashes SHA-256 das imagens originais
# e salva em task-dep/original_hashes.json
python3 <<'EOF'
import os, hashlib, json

# Diretório de backup das imagens originais
image_backup_dir = f"{os.getcwd()}/images-backup"
# Diretório onde as imagens serão usadas para conversão
image_dir = f"{os.getcwd()}/images"

# Copia as imagens de backup para a pasta images
os.system(f"cp -r {image_backup_dir}/* {image_dir}/")

# Diretório e arquivo onde os hashes serão salvos
output_dir = f"{os.getcwd()}/task-dep"
output_file = os.path.join(output_dir, "original_hashes.json")

print(f"{image_dir}\n{output_dir}\n{output_file}")
os.system(f"ls -la {output_dir}")

hashes = {}

# Calcula hash SHA-256 de cada arquivo em image_dir
for filename in os.listdir(image_dir):
    path = os.path.join(image_dir, filename)
    print(f"Hashing {path}...")
    if os.path.isfile(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        hashes[filename] = h.hexdigest()

# Salva os hashes em JSON (para possível verificação futura)
with open(output_file, "w") as f:
    json.dump(hashes, f, indent=2)
    f.flush()

print(f"✅ Saved hashes to {output_file}")
EOF

# Pequena pausa (pode ser útil se o ambiente estiver inicializando algo em paralelo)
sleep 20

# Se estiver em ambiente com apt-get (ex: Debian/Ubuntu),
# tenta instalar dependências úteis (zip e libs de imagem),
# mas só se estiver rodando como root.
if command -v apt-get >/dev/null 2>&1; then
    if [ "$EUID" -eq 0 ]; then
        apt-get update
        apt-get install -y zip libjpeg-dev libpng-dev libtiff-dev libgif-dev
    else
        echo "⚠️ Skipping apt-get install (run with sudo if you need those packages)."
    fi
fi

# Caminhos dos binários cwebp e dwebp dentro de task-dep
CWEBP="$PWD/task-dep/bin/cwebp"
DWEBP="$PWD/task-dep/bin/dwebp"

# Diretórios raiz do projeto e de imagens
DIR=$PWD
INPUT_DIR="$PWD/images"
OUTPUT_DIR="$PWD/optimized"

# Garante que o diretório de saída existe
mkdir -p "$OUTPUT_DIR"

# Entra na pasta de imagens para simplificar caminhos relativos
cd images

# Ativa glob case-insensitive (pega .JPG, .Jpeg, etc.)
shopt -s nocaseglob

# Loop principal: percorre todas as imagens .jpg/.jpeg/.png/ .webp/ .tif/ .tiff
for img in *.jpg *.jpeg *.png *.webp *.tif *.tiff; do
    # Se não existir nenhum arquivo que case com o glob, pula
    [ -e "$img" ] || continue

    filename=$(basename "$img")
    # Caminho de saída: optimized/<nome>.webp
    output="$OUTPUT_DIR/${filename%.*}.webp"
    
    # Tamanho original da imagem, em bytes
    original_size=$(stat -c%s "$img")
    ((total+=original_size))
    
    # Começamos tentando com a qualidade default (compression_level)
    quality=$compression_level
    optimized_size=0
    
    # Função auxiliar para encodar com determinada qualidade
    # Sempre remove o arquivo anterior antes de gerar o novo.
    encode_with_quality() {
        rm -f "$output"
        "$CWEBP" -q "$1" "${CWEBP_EXTRA_ARGS[@]}" "$img" -o "$output"
    }
    
    # Primeira tentativa de conversão com a qualidade inicial
    encode_with_quality "$quality"
    optimized_size=$(stat -c%s "$output")
    
    # Enquanto:
    # - o arquivo ainda estiver maior que o limite TARGET_BYTES
    # - E ainda tivermos espaço para reduzir quality acima de MIN_QUALITY
    # vamos reduzir a qualidade em degraus (QUALITY_STEP),
    # reencodando a cada iteração.
    while (( optimized_size > TARGET_BYTES )) && (( quality > MIN_QUALITY )); do
        # Reduz qualidade em QUALITY_STEP (ex.: 80 → 75 → 70...)
        quality=$((quality - QUALITY_STEP))

        # Garante que não passa abaixo do mínimo configurado
        if (( quality < MIN_QUALITY )); then
            quality=$MIN_QUALITY
        fi

        # Reencoda com a qualidade ajustada
        encode_with_quality "$quality"
        optimized_size=$(stat -c%s "$output")

        # Se já chegamos exatamente em MIN_QUALITY, não adianta descer mais
        if (( quality == MIN_QUALITY )); then
            break
        fi
    done
    
    # Se ainda está maior que o limite, e RESORT_TO_SIZE=true,
    # usamos o modo -size do cwebp para tentar bater o alvo em bytes.
    if (( optimized_size > TARGET_BYTES )) && [[ "${RESORT_TO_SIZE,,}" == "true" ]]; then
        rm -f "$output"
        "$CWEBP" -size "$TARGET_BYTES" "${CWEBP_EXTRA_ARGS[@]}" "$img" -o "$output" || true
        # Se der erro ou não gerar arquivo, definimos 0 como tamanho
        optimized_size=$(stat -c%s "$output" 2>/dev/null || echo 0)
    fi
    
    # Se por algum motivo não foi possível gerar o arquivo,
    # registramos como falha e seguimos para a próxima imagem.
    if (( optimized_size == 0 )); then
        echo "⚠️ Failed to create optimized file for $filename"
        oversized_images+=("$filename (conversion failed)")
        continue
    fi
    
    # Neste ponto, temos um arquivo .webp gerado.
    # Se ainda estiver acima do limite, registramos como “oversized”
    # para relatório, mas seguimos em frente.
    if (( optimized_size > TARGET_BYTES )); then
        echo "⚠️ $filename still above ${MAX_SIZE_KB} KB (actual: $((optimized_size / 1024)) KB)"
        oversized_images+=("$filename ($((optimized_size / 1024)) KB)")
    else
        # Caso contrário, log de sucesso com tamanho final e qualidade usada
        echo "✅ $filename optimized to $((optimized_size / 1024)) KB at quality ${quality}"
    fi
    
    # Soma o tamanho otimizado ao total
    ((optimized+=optimized_size))
done

# Desativa o glob case-insensitive
shopt -u nocaseglob

# Pequena pausa (pode ser útil se o ambiente estiver ainda fechando algo)
sleep 5

# Volta para o diretório raiz do projeto
cd ..

# Cria um zip com todas as imagens otimizadas
zip -j "$DIR/optimized.zip" "$OUTPUT_DIR"

# Resumo dos tamanhos total original x otimizado (em KB)
echo "Total size non-optimized: $((total / 1024)) KB."
echo "Total size optimized: $((optimized / 1024)) KB.\n"
