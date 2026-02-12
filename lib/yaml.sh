#!/bin/bash
# HomeStack — YAML parser
# Simple parser for the controlled app.yaml format

# Get a simple key: value pair
# Usage: yaml_get <file> <key>
yaml_get() {
  local file="$1" key="$2"
  sed -n "s/^${key}:[[:space:]]*//p" "$file" | head -1 | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/"
}

# Get an inline array: key: [item1, item2]
# Usage: yaml_get_array <file> <key>
yaml_get_array() {
  local file="$1" key="$2"
  local line
  line=$(yaml_get "$file" "$key")
  echo "$line" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -v '^$'
}

# Parse the secrets block from app.yaml
# Returns lines in format: key|prompt|default|generate|length
# Usage: yaml_parse_secrets <file>
yaml_parse_secrets() {
  local file="$1"
  local in_secrets=0
  local key="" prompt="" default_val="" generate="false" length="32"

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Detect start of secrets block
    if [[ "$line" =~ ^secrets:[[:space:]]*$ ]]; then
      in_secrets=1
      continue
    fi

    # Exit secrets block on non-indented line (not blank)
    if [[ $in_secrets -eq 1 ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
      [[ -n "$key" ]] && echo "${key}|${prompt}|${default_val}|${generate}|${length}"
      break
    fi

    if [[ $in_secrets -eq 1 ]]; then
      # New secret entry
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*key:[[:space:]]*(.*) ]]; then
        [[ -n "$key" ]] && echo "${key}|${prompt}|${default_val}|${generate}|${length}"
        key="${BASH_REMATCH[1]}"
        prompt="" default_val="" generate="false" length="32"
      elif [[ "$line" =~ ^[[:space:]]*prompt:[[:space:]]*\"(.*)\" ]]; then
        prompt="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*prompt:[[:space:]]*(.*) ]]; then
        prompt="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*default:[[:space:]]*(.*) ]]; then
        default_val="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*generate:[[:space:]]*(.*) ]]; then
        generate="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*length:[[:space:]]*(.*) ]]; then
        length="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$file"

  # Output last secret if we hit EOF while still in secrets block
  [[ $in_secrets -eq 1 && -n "$key" ]] && echo "${key}|${prompt}|${default_val}|${generate}|${length}"
}
