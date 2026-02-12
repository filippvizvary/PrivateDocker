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
  echo "$line" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | { grep -v '^$' || true; }
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
  if [[ $in_secrets -eq 1 && -n "$key" ]]; then
    echo "${key}|${prompt}|${default_val}|${generate}|${length}"
  fi
  return 0
}

# Parse the health_checks block from test.yaml
# Returns lines in format: url|method|expected_status|body_contains|timeout
# Usage: yaml_parse_health_checks <file>
yaml_parse_health_checks() {
  local file="$1"
  local in_block=0
  local url="" method="GET" expected_status="200" body_contains="" timeout="10"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^health_checks:[[:space:]]*$ ]]; then
      in_block=1
      continue
    fi

    # Exit block on non-indented, non-blank line
    if [[ $in_block -eq 1 ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
      [[ -n "$url" ]] && echo "${url}|${method}|${expected_status}|${body_contains}|${timeout}"
      break
    fi

    if [[ $in_block -eq 1 ]]; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*url:[[:space:]]*(.*) ]]; then
        [[ -n "$url" ]] && echo "${url}|${method}|${expected_status}|${body_contains}|${timeout}"
        url="${BASH_REMATCH[1]}"
        method="GET" expected_status="200" body_contains="" timeout="10"
      elif [[ "$line" =~ ^[[:space:]]*method:[[:space:]]*(.*) ]]; then
        method="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*expected_status:[[:space:]]*(.*) ]]; then
        expected_status="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*body_contains:[[:space:]]*\"(.*)\" ]]; then
        body_contains="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*body_contains:[[:space:]]*(.*) ]]; then
        body_contains="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*timeout:[[:space:]]*(.*) ]]; then
        timeout="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$file"

  if [[ $in_block -eq 1 && -n "$url" ]]; then
    echo "${url}|${method}|${expected_status}|${body_contains}|${timeout}"
  fi
  return 0
}

# Parse the exec_checks block from test.yaml
# Returns lines in format: container|command|expected_output
# Usage: yaml_parse_exec_checks <file>
yaml_parse_exec_checks() {
  local file="$1"
  local in_block=0
  local container="" command="" expected_output=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^exec_checks:[[:space:]]*$ ]]; then
      in_block=1
      continue
    fi

    if [[ $in_block -eq 1 ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
      [[ -n "$container" ]] && echo "${container}|${command}|${expected_output}"
      break
    fi

    if [[ $in_block -eq 1 ]]; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*container:[[:space:]]*(.*) ]]; then
        [[ -n "$container" ]] && echo "${container}|${command}|${expected_output}"
        container="${BASH_REMATCH[1]}"
        command="" expected_output=""
      elif [[ "$line" =~ ^[[:space:]]*command:[[:space:]]*\"(.*)\" ]]; then
        command="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*command:[[:space:]]*(.*) ]]; then
        command="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*expected_output:[[:space:]]*\"(.*)\" ]]; then
        expected_output="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*expected_output:[[:space:]]*(.*) ]]; then
        expected_output="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$file"

  if [[ $in_block -eq 1 && -n "$container" ]]; then
    echo "${container}|${command}|${expected_output}"
  fi
  return 0
}
