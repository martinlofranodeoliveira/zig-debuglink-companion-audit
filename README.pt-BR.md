# Auditor de Símbolos Auxiliares Debuglink em Zig

[![CI](https://github.com/martinlofranodeoliveira/zig-debuglink-companion-audit/actions/workflows/ci.yml/badge.svg)](https://github.com/martinlofranodeoliveira/zig-debuglink-companion-audit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.14%2B%20%7C%200.17-orange.svg)](https://ziglang.org)

Um auditor independente e determinístico de símbolos de depuração auxiliares ELF (`.gnu_debuglink`) desenvolvido em Zig puro. O projeto inspeciona metadados ELF utilizando as bibliotecas `libelf` e `gelf` e verifica arquivos de depuração acompanhantes contra referências padrão do GNU `objcopy` e `readelf`.

[**Read in English**](README.md)

---

## Funcionalidades Principais

- **Manifestos Explícitos e Seguros**: Audita apenas arquivos ELF e companheiros de depuração explicitamente fornecidos. Nunca consulta diretórios do sistema ou armazéns de símbolos do host.
- **Conformidade com a Especificação GNU BFD Debuglink**:
  - Valida seção `.gnu_debuglink` única; rejeita seções duplicadas.
  - Exige terminação NUL (`\0`) exata e preenchimento alinhado a 4 bytes com zeros.
  - Decodifica o campo CRC32 na ordem de bytes do alvo (little-endian ou big-endian) segundo o cabeçalho ELF (`EI_DATA`).
  - Rejeita bytes excedentes após o campo CRC.
- **Verificação Completa de Integridade CRC-32**: Calcula o algoritmo CRC-32 IEEE 802.3 (`0xEDB88320`) sobre todos os bytes do arquivo de depuração através de janela em streaming $O(1)$.
- **Verificação de Compatibilidade de Arquitetura**: Garante que o arquivo acompanhante possua a mesma classe (`ELFCLASS32`/`ELFCLASS64`), codificação de dados e arquitetura (`e_machine`) do binário principal.
- **Inspeção de Build ID e Seções de Depuração**: Confirma a presença de seções `.debug_*` e compara os identificadores GNU Build ID (`.note.gnu.build-id`).
- **Defesas Contra Adulteração e Links Simbólicos**:
  - Rejeita links simbólicos antes do acesso via chamada POSIX `lstat`.
  - Compara metadados do descritor de arquivo antes e após a leitura (`fstat`) para detectar modificações concorrentes.
  - Aplica limites estritos de recursos (tamanho máximo de 1 GiB, caminhos de até 4096 bytes, máximo de 10.000 seções).

---

## Instalação e Requisitos

### Requisitos
- **Zig**: 0.14+ ou 0.17+
- **libelf**: `libelf-dev` (pacote `elfutils`)
- **Biblioteca C**: GNU `libc` ou musl
- **binutils** *(opcional, para reconstruir fixtures)*: `gcc`, `objcopy`, `readelf`

### Compilação a partir do Código-Fonte

```sh
# Clonar o repositório
git clone https://github.com/martinlofranodeoliveira/zig-debuglink-companion-audit.git
cd zig-debuglink-companion-audit

# Compilar o binário em modo ReleaseSafe
zig build-exe -lc -lelf src/main.zig -femit-bin=audit -O ReleaseSafe
```

---

## Exemplos de Uso

### 1. Auditoria Direta de Arquivos

```sh
./audit --elf fixtures/sample.bin --debug fixtures/sample.debug
```

Saída de Exemplo:
```
Verdict: Matched
  Main ELF:          fixtures/sample.bin
  Companion:         fixtures/sample.debug
  Debuglink Name:    sample.debug
  Expected CRC32:    0x8a5d42ff
  Computed CRC32:    0x8a5d42ff
  ELF Class:         ELF64
  ELF Machine:       0x003e
  Debug Sections:    true
  Main Build-ID:     57b5856da998b70b4ba071220f44655f0070b8da
  Companion Build-ID:57b5856da998b70b4ba071220f44655f0070b8da
  Build-IDs Match:   true
```

### 2. Auditoria Baseada em Manifesto JSON

```sh
./audit --manifest fixtures/manifest.json
```

Estrutura do manifesto (`fixtures/manifest.json`):
```json
{
  "entries": [
    {
      "id": "sample-companion-match",
      "elf": "fixtures/sample.bin",
      "companion": "fixtures/sample.debug"
    }
  ]
}
```

### 3. Saída Estruturada em JSON

```sh
./audit --manifest fixtures/manifest.json --json
```

Saída:
```json
[
  {
    "id": "sample-companion-match",
    "verdict": "Matched",
    "main_elf": "fixtures/sample.bin",
    "companion": "fixtures/sample.debug",
    "debuglink_name": "sample.debug",
    "expected_crc": 2321367807,
    "actual_crc": 2321367807,
    "elf_class": 2,
    "elf_machine": 62,
    "has_debug_sections": true,
    "main_build_id": "57b5856da998b70b4ba071220f44655f0070b8da",
    "companion_build_id": "57b5856da998b70b4ba071220f44655f0070b8da",
    "build_ids_agree": true,
    "error_message": null
  }
]
```

### 4. Suíte de Asserções Embutida

```sh
./audit --assert
```

Valida automaticamente 9 cenários essenciais:
1. Correspondência perfeita de binário e acompanhante divididos por `objcopy`.
2. Adulteração de 1 byte no acompanhante produz `CrcMismatch`.
3. Nome de arquivo acompanhante incorreto produz `NameMismatch`.
4. Acompanhante sem seções `.debug_*` produz `MissingDebugSections`.
5. Binário sem seção `.gnu_debuglink` produz `MissingDebuglink`.
6. Arquivo acompanhante inacessível produz `MissingCompanion`.
7. Entrada apontando para link simbólico é rejeitada (`SymlinkRejected`).
8. Vetores de decodificação little-endian e big-endian executam com sucesso.
9. Cargas malformadas (truncadas, com padding incorreto ou sem terminador NUL) são rejeitadas com erro estrutural.

---

## Testes Offline

O projeto inclui rotinas de validação 100% desconectadas da rede:

```sh
# Executar a suíte completa de testes offline
sh scripts/test-offline.sh

# Executar a demonstração com asserções
sh scripts/demo-offline.sh --assert
```

---

## Documentação Técnica

- [Especificação de Contratos de Entrada e Saída](docs/contract.md)
- [Arquitetura e Projeto Técnico](docs/design.md)
- [Especificação de Produto](PRODUCT.md)
- [Histórico de Mudanças (Changelog)](CHANGELOG.md)
- [Política de Segurança](SECURITY.md)

---

## Licença

Licença MIT © 2026 [Lofrano Tecnologia](https://lofranotecnologia.com.br).
Desenvolvido por Martin Lofrano de Oliveira.
