# TweakDB Schema Reference

## Overview

TweakDB is Cyberpunk 2077's runtime database for game data including items, stats, vehicles, NPCs, and more. TweakXL enables runtime modification of this database.

## TweakDBID Format

```
BaseGame.Weapon_Rifle_Assault_Militech_Ajay
├─────────────────────────────────────────┤
           TweakDBID (string form)

Hash: FNV1a64 of the string
```

## Record Types

### Base Record

All records inherit from `gamedataRecord`:

```yaml
BaseGame.ExampleRecord:
  $type: gamedataItem_Record  # Required: record type
  $base: BaseGame.ParentRecord  # Optional: inheritance
```

### Common Record Types

#### Items (gamedataItem_Record)

```yaml
Items.MyCustomWeapon:
  $type: gamedataItem_Record
  displayName: LocKey#12345
  localizedDescription: LocKey#12346
  quality: Quality.Legendary
  itemType: ItemType.Wea_Rifle
  tags:
    - !append WeaponMod
  buyPrice:
    - Price.BaseWeaponPrice
  sellPrice:
    - Price.BaseWeaponSellPrice
  statModifiers:
    - !append MyCustomStatModifier
```

#### Stats (gamedataStat_Record)

```yaml
BaseStats.MyCustomStat:
  $type: gamedataStat_Record
  enumName: MyCustomStat
  min: 0.0
  max: 100.0
  flags:
    - StatFlag.IsPersistent
```

#### Stat Modifiers (gamedataStatModifier_Record)

```yaml
StatModifiers.MyDamageBoost:
  $type: gamedataConstantStatModifier_Record
  modifierType: Additive
  statType: BaseStats.DPS
  value: 50.0
```

#### Vehicles (gamedataVehicle_Record)

```yaml
Vehicle.MyCustomCar:
  $type: gamedataVehicle_Record
  displayName: LocKey#56789
  manufacturer: UIText.Rayfield
  vehicleType: VehicleType.Car
  topSpeed: 250.0
```

## Value Types

### Primitives

```yaml
intValue: 42
floatValue: 3.14
boolValue: true
stringValue: "Hello"
```

### CName (Interned String)

```yaml
cnameValue: n"MyNamedValue"
```

### TweakDBID Reference

```yaml
recordRef: Items.BaseWeapon  # Reference to another record
```

### Resource Path

```yaml
resourcePath: r"base\gameplay\items\weapons\my_weapon.ent"
```

### Arrays

```yaml
simpleArray:
  - value1
  - value2

# Append to existing array
existingArray:
  - !append newValue

# Prepend to array  
existingArray:
  - !prepend firstValue

# Remove from array
existingArray:
  - !remove valueToRemove
```

### Foreign Keys

```yaml
foreignKey: 
  $type: gamedataItemForeignKey_Record
  reference: Items.TargetItem
```

## Operations

### Create New Record

```yaml
MyMod.NewWeapon:
  $type: gamedataItem_Record
  displayName: LocKey#99999
  # ... all required fields
```

### Clone Existing Record

```yaml
MyMod.ClonedWeapon:
  $base: Items.Preset_Achilles_Default
  displayName: LocKey#99998
  # Override specific fields
```

### Modify Existing Record

```yaml
Items.Preset_Achilles_Default:
  statModifiers:
    - !append MyMod.ExtraStatModifier
```

## JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "TweakXL YAML Schema",
  "type": "object",
  "patternProperties": {
    "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$": {
      "$ref": "#/definitions/TweakRecord"
    }
  },
  "definitions": {
    "TweakRecord": {
      "type": "object",
      "properties": {
        "$type": {
          "type": "string",
          "description": "Record type (required for new records)"
        },
        "$base": {
          "type": "string",
          "description": "Parent record for cloning"
        }
      },
      "additionalProperties": {
        "$ref": "#/definitions/TweakValue"
      }
    },
    "TweakValue": {
      "oneOf": [
        { "type": "integer" },
        { "type": "number" },
        { "type": "boolean" },
        { "type": "string" },
        { "$ref": "#/definitions/TweakArray" },
        { "$ref": "#/definitions/TweakObject" }
      ]
    },
    "TweakArray": {
      "type": "array",
      "items": {
        "$ref": "#/definitions/TweakValue"
      }
    },
    "TweakObject": {
      "type": "object",
      "properties": {
        "$type": { "type": "string" }
      },
      "additionalProperties": {
        "$ref": "#/definitions/TweakValue"
      }
    }
  }
}
```

## Common Record Type Reference

| Type | Description |
|------|-------------|
| `gamedataItem_Record` | Base item |
| `gamedataWeaponItem_Record` | Weapon items |
| `gamedataClothingItem_Record` | Clothing/armor |
| `gamedataConsumableItem_Record` | Consumables |
| `gamedataStat_Record` | Stat definitions |
| `gamedataStatModifier_Record` | Stat modifier base |
| `gamedataConstantStatModifier_Record` | Constant stat mod |
| `gamedataCombinedStatModifier_Record` | Combined stat mod |
| `gamedataVehicle_Record` | Vehicles |
| `gamedataNPCType_Record` | NPC definitions |
| `gamedataAttack_Record` | Attack definitions |
| `gamedataStatusEffect_Record` | Status effects |
| `gamedataPerk_Record` | Perks |
| `gamedataLocKey_Record` | Localization keys |
