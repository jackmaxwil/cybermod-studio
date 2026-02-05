# ArchiveXL Schema Reference

## Overview

ArchiveXL enables extending game resources without overwriting base files. Configuration is via `.xl` YAML files placed in `archive/pc/mod/`.

## File Structure

```yaml
# mymod.xl
factories:
  - path/to/factory.csv

localization:
  onscreens:
    en-us: path/to/onscreens_en.json
    de-de: path/to/onscreens_de.json

resource:
  scope:
    - base\resource\to\extend.app: mymod\extension.app
  
  link:
    - mymod\symbolic.app: base\original.app
```

## Extension Types

### 1. Factory Index

Register new entity factories (CSV format):

```yaml
factories:
  - mymod\factories\items.csv
  - mymod\factories\vehicles.csv
```

**CSV Format:**

```csv
name,path,preload
my_item,base\gameplay\items\my_item.ent,false
my_vehicle,base\vehicles\my_vehicle.ent,true
```

### 2. Localization

#### OnScreens (UI Text)

```yaml
localization:
  onscreens:
    en-us: mymod\localization\en-us\onscreens.json
    de-de: mymod\localization\de-de\onscreens.json
```

**JSON Format:**

```json
{
  "entries": [
    {
      "primaryKey": "0",
      "secondaryKey": "MyMod-ItemName",
      "femaleVariant": "Custom Item Name"
    }
  ]
}
```

#### Subtitles

```yaml
localization:
  subtitles:
    en-us: mymod\localization\en-us\subtitles.json
```

#### Voice Overs

```yaml
localization:
  voiceovers:
    en-us: mymod\localization\en-us\voiceovers.json
```

#### Lip Syncs

```yaml
localization:
  lipsyncs:
    en-us: mymod\localization\en-us\lipsyncs.animlipsync
```

### 3. Resource Scope

Extend existing resources without overwriting:

```yaml
resource:
  scope:
    # Original resource: Extension resource
    - base\gameplay\gui\widgets\inventory.inkwidget: mymod\widgets\inventory_ext.inkwidget
```

### 4. Resource Link

Create symbolic links between resources:

```yaml
resource:
  link:
    # Target: Source (target becomes alias for source)
    - mymod\alias.app: base\original.app
```

### 5. Resource Patch

Patch existing resources by merging:

```yaml
resource:
  patch:
    - base\quest\main.questphase
```

### 6. Garment Extensions

#### Dynamic Appearances

```yaml
garment:
  appearances:
    - entity: base\characters\player\v.ent
      component: torso
      appearance: my_custom_appearance
      mesh: mymod\meshes\custom_torso.mesh
```

#### Visual Tags

```yaml
garment:
  tags:
    - name: MyCustomTag
      hide:
        - torso_inner
        - arms_inner
```

#### Component Overrides

```yaml
garment:
  overrides:
    - entity: base\characters\player\v.ent
      appearance: default
      components:
        torso:
          mesh: mymod\meshes\torso.mesh
```

### 7. Customization

Add character customization options:

```yaml
customization:
  male:
    hair:
      - mymod\customization\male\hair_01.app
    eyes:
      - mymod\customization\male\eyes_01.app
  
  female:
    hair:
      - mymod\customization\female\hair_01.app
```

### 8. Animation

Register custom animations:

```yaml
animation:
  sets:
    - entity: base\characters\player\v.ent
      component: root
      animset: mymod\animations\custom.animset
      priority: 1
```

### 9. Attachment Slots

Define custom attachment slots:

```yaml
attachment:
  slots:
    - name: MyCustomSlot
      parent: Torso
      dependsOn:
        - Arms
      visual_tags_check:
        - MyTag
```

### 10. Journal

Extend quest journal:

```yaml
journal:
  entries:
    - mymod\journal\quest_entry.journal
  
  mappins:
    - id: my_mappin
      position: [100.0, 200.0, 50.0]
      type: QuestMappin
```

### 11. Quest Phase

Patch quest phases:

```yaml
questphase:
  patches:
    - base\quest\main\act1.questphase
  
  nodes:
    - phase: act1
      from: node_123
      to: mymod_custom_node
```

### 12. World Streaming

Modify streaming sectors:

```yaml
streaming:
  sectors:
    - base\worlds\03_night_city\sectors\sector_01.streamingsector
  
  workspots:
    - sector: sector_01
      position: [100.0, 200.0, 50.0]
      rotation: [0.0, 0.0, 0.0, 1.0]
```

## JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ArchiveXL Configuration Schema",
  "type": "object",
  "properties": {
    "factories": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Factory CSV file paths"
    },
    "localization": {
      "$ref": "#/definitions/Localization"
    },
    "resource": {
      "$ref": "#/definitions/Resource"
    },
    "garment": {
      "$ref": "#/definitions/Garment"
    },
    "customization": {
      "$ref": "#/definitions/Customization"
    },
    "animation": {
      "$ref": "#/definitions/Animation"
    },
    "attachment": {
      "$ref": "#/definitions/Attachment"
    },
    "journal": {
      "$ref": "#/definitions/Journal"
    },
    "questphase": {
      "$ref": "#/definitions/QuestPhase"
    },
    "streaming": {
      "$ref": "#/definitions/Streaming"
    }
  },
  "definitions": {
    "Localization": {
      "type": "object",
      "properties": {
        "onscreens": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        },
        "subtitles": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        },
        "voiceovers": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        },
        "lipsyncs": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        }
      }
    },
    "Resource": {
      "type": "object",
      "properties": {
        "scope": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": { "type": "string" }
          }
        },
        "link": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": { "type": "string" }
          }
        },
        "patch": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "Garment": {
      "type": "object",
      "properties": {
        "appearances": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "entity": { "type": "string" },
              "component": { "type": "string" },
              "appearance": { "type": "string" },
              "mesh": { "type": "string" }
            },
            "required": ["entity", "appearance"]
          }
        },
        "tags": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "hide": {
                "type": "array",
                "items": { "type": "string" }
              }
            },
            "required": ["name"]
          }
        }
      }
    },
    "Customization": {
      "type": "object",
      "properties": {
        "male": { "$ref": "#/definitions/CustomizationOptions" },
        "female": { "$ref": "#/definitions/CustomizationOptions" }
      }
    },
    "CustomizationOptions": {
      "type": "object",
      "additionalProperties": {
        "type": "array",
        "items": { "type": "string" }
      }
    },
    "Animation": {
      "type": "object",
      "properties": {
        "sets": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "entity": { "type": "string" },
              "component": { "type": "string" },
              "animset": { "type": "string" },
              "priority": { "type": "integer" }
            },
            "required": ["entity", "animset"]
          }
        }
      }
    },
    "Attachment": {
      "type": "object",
      "properties": {
        "slots": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "parent": { "type": "string" },
              "dependsOn": {
                "type": "array",
                "items": { "type": "string" }
              }
            },
            "required": ["name"]
          }
        }
      }
    },
    "Journal": {
      "type": "object",
      "properties": {
        "entries": {
          "type": "array",
          "items": { "type": "string" }
        },
        "mappins": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "id": { "type": "string" },
              "position": {
                "type": "array",
                "items": { "type": "number" },
                "minItems": 3,
                "maxItems": 3
              },
              "type": { "type": "string" }
            },
            "required": ["id", "position"]
          }
        }
      }
    },
    "QuestPhase": {
      "type": "object",
      "properties": {
        "patches": {
          "type": "array",
          "items": { "type": "string" }
        },
        "nodes": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "phase": { "type": "string" },
              "from": { "type": "string" },
              "to": { "type": "string" }
            }
          }
        }
      }
    },
    "Streaming": {
      "type": "object",
      "properties": {
        "sectors": {
          "type": "array",
          "items": { "type": "string" }
        },
        "workspots": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "sector": { "type": "string" },
              "position": {
                "type": "array",
                "items": { "type": "number" }
              },
              "rotation": {
                "type": "array",
                "items": { "type": "number" }
              }
            }
          }
        }
      }
    }
  }
}
```

## Validation Rules

1. **Path Format**: Resource paths must use backslashes and be relative
2. **File Existence**: Referenced files must exist in the archive
3. **Language Codes**: Use ISO 639-1 codes (en-us, de-de, etc.)
4. **Entity References**: Entity paths must point to valid .ent files
5. **Mesh References**: Mesh paths must point to valid .mesh files
