#include "engine.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const float kWorldHalfWidth = 1400.0f;
static const float kWorldHalfHeight = 980.0f;
static const float kPickupRadius = 72.0f;
static const float kPlayerRadiusStand = 18.0f;
static const float kPlayerRadiusCrouch = 15.0f;
static const float kPlayerRadiusProne = 12.0f;
static const float kEnemyRadius = 18.0f;
static const size_t kCollectionTarget = 8;
static MissionType sMissionCursor = MissionType_CacheRaid;

static float clampf(float value, float minimum, float maximum) {
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

static Vec2 vec2_make(float x, float y) {
    Vec2 value;
    value.x = x;
    value.y = y;
    return value;
}

static Vec2 vec2_add(Vec2 a, Vec2 b) {
    return vec2_make(a.x + b.x, a.y + b.y);
}

static Vec2 vec2_sub(Vec2 a, Vec2 b) {
    return vec2_make(a.x - b.x, a.y - b.y);
}

static Vec2 vec2_scale(Vec2 value, float scale) {
    return vec2_make(value.x * scale, value.y * scale);
}

static float vec2_length(Vec2 value) {
    return sqrtf((value.x * value.x) + (value.y * value.y));
}

static Vec2 vec2_normalize(Vec2 value) {
    float length = vec2_length(value);
    if (length < 0.0001f) {
        return vec2_make(1.0f, 0.0f);
    }
    return vec2_scale(value, 1.0f / length);
}

static float vec2_distance(Vec2 a, Vec2 b) {
    return vec2_length(vec2_sub(a, b));
}

static float vec2_dot(Vec2 a, Vec2 b) {
    return (a.x * b.x) + (a.y * b.y);
}

static Vec2 vec2_rotate(Vec2 value, float radians) {
    float sine = sinf(radians);
    float cosine = cosf(radians);
    return vec2_make((value.x * cosine) - (value.y * sine), (value.x * sine) + (value.y * cosine));
}

static void copy_name(char *destination, size_t destinationCount, const char *source) {
    if (destinationCount == 0) {
        return;
    }
    snprintf(destination, destinationCount, "%s", source);
}

static void set_event(GameState *state, const char *event) {
    copy_name(state->lastEvent, sizeof(state->lastEvent), event);
}

static unsigned int fire_mode_mask(FireMode mode) {
    return 1u << (unsigned int) mode;
}

static const char *fire_mode_name(FireMode mode) {
    switch (mode) {
        case FireMode_Semi:
            return "Semi";
        case FireMode_Burst:
            return "Burst";
        case FireMode_Auto:
            return "Auto";
        default:
            return "Semi";
    }
}

static const char *stance_name(Stance stance) {
    switch (stance) {
        case Stance_Stand:
            return "Standing";
        case Stance_Crouch:
            return "Crouched";
        case Stance_Prone:
            return "Prone";
        default:
            return "Standing";
    }
}

static int *ammo_reserve(Player *player, AmmoType ammoType) {
    switch (ammoType) {
        case AmmoType_556:
            return &player->ammo556;
        case AmmoType_9mm:
            return &player->ammo9mm;
        case AmmoType_Shell:
            return &player->ammoShell;
        case AmmoType_None:
        default:
            return &player->ammo556;
    }
}

static float player_radius(const Player *player) {
    switch (player->stance) {
        case Stance_Crouch:
            return kPlayerRadiusCrouch;
        case Stance_Prone:
            return kPlayerRadiusProne;
        case Stance_Stand:
        default:
            return kPlayerRadiusStand;
    }
}

static InventoryItem make_weapon(const char *name,
                                 WeaponClass weaponClass,
                                 AmmoType ammoType,
                                 int capacity,
                                 int rounds,
                                 float damage,
                                 float range,
                                 bool suppressed,
                                 float recoil,
                                 float muzzleVelocity,
                                 FireMode fireMode,
                                 unsigned int supportedFireModes,
                                 bool supportsSuppressor,
                                 bool supportsOptic,
                                 bool opticMounted) {
    InventoryItem item;
    memset(&item, 0, sizeof(item));
    item.active = true;
    item.kind = (weaponClass == WeaponClass_Knife) ? ItemKind_Blade : ItemKind_Gun;
    item.ammoType = ammoType;
    item.weaponClass = weaponClass;
    copy_name(item.name, sizeof(item.name), name);
    item.quantity = 1;
    item.magazineCapacity = capacity;
    item.roundsInMagazine = rounds;
    item.damage = damage;
    item.range = range;
    item.suppressed = suppressed;
    item.recoil = recoil;
    item.muzzleVelocity = muzzleVelocity;
    item.fireMode = fireMode;
    item.supportedFireModes = supportedFireModes;
    item.supportsSuppressor = supportsSuppressor;
    item.supportsOptic = supportsOptic;
    item.opticMounted = opticMounted;
    return item;
}

static InventoryItem make_support_item(const char *name, ItemKind kind, AmmoType ammoType, int quantity, int capacity) {
    InventoryItem item;
    memset(&item, 0, sizeof(item));
    item.active = true;
    item.kind = kind;
    item.ammoType = ammoType;
    item.weaponClass = WeaponClass_None;
    copy_name(item.name, sizeof(item.name), name);
    item.quantity = quantity;
    item.magazineCapacity = capacity;
    return item;
}

static WorldItem make_world_weapon(const char *name,
                                   WeaponClass weaponClass,
                                   AmmoType ammoType,
                                   Vec2 position,
                                   int capacity,
                                   int rounds,
                                   float damage,
                                   bool suppressed,
                                   float recoil,
                                   float muzzleVelocity,
                                   FireMode fireMode,
                                   unsigned int supportedFireModes,
                                   bool supportsSuppressor,
                                   bool supportsOptic,
                                   bool opticMounted) {
    WorldItem item;
    memset(&item, 0, sizeof(item));
    item.active = true;
    item.kind = (weaponClass == WeaponClass_Knife) ? ItemKind_Blade : ItemKind_Gun;
    item.ammoType = ammoType;
    item.weaponClass = weaponClass;
    item.position = position;
    copy_name(item.name, sizeof(item.name), name);
    item.quantity = 1;
    item.magazineCapacity = capacity;
    item.roundsInMagazine = rounds;
    item.damage = damage;
    item.suppressed = suppressed;
    item.recoil = recoil;
    item.muzzleVelocity = muzzleVelocity;
    item.fireMode = fireMode;
    item.supportedFireModes = supportedFireModes;
    item.supportsSuppressor = supportsSuppressor;
    item.supportsOptic = supportsOptic;
    item.opticMounted = opticMounted;
    return item;
}

static WorldItem make_world_supply(const char *name,
                                   ItemKind kind,
                                   AmmoType ammoType,
                                   Vec2 position,
                                   int quantity,
                                   int capacity,
                                   bool suppressed) {
    WorldItem item;
    memset(&item, 0, sizeof(item));
    item.active = true;
    item.kind = kind;
    item.ammoType = ammoType;
    item.weaponClass = WeaponClass_None;
    item.position = position;
    copy_name(item.name, sizeof(item.name), name);
    item.quantity = quantity;
    item.magazineCapacity = capacity;
    item.suppressed = suppressed;
    return item;
}

static WorldItem make_world_objective(const char *name, Vec2 position) {
    return make_world_supply(name, ItemKind_Objective, AmmoType_None, position, 1, 0, false);
}

static int add_inventory_item(Player *player, InventoryItem item) {
    if (player->inventoryCount >= GAME_MAX_INVENTORY) {
        return -1;
    }

    player->inventory[player->inventoryCount] = item;
    player->inventoryCount += 1;
    return player->inventoryCount - 1;
}

static void add_world_item(GameState *state, WorldItem item) {
    size_t index;
    for (index = 0; index < GAME_MAX_ITEMS; index += 1) {
        if (!state->worldItems[index].active) {
            state->worldItems[index] = item;
            return;
        }
    }
}

static void add_enemy(GameState *state, Vec2 position, float patrolPhase) {
    size_t index;
    for (index = 0; index < GAME_MAX_ENEMIES; index += 1) {
        if (!state->enemies[index].active) {
            state->enemies[index].active = true;
            state->enemies[index].position = position;
            state->enemies[index].velocity = vec2_make(0.0f, 0.0f);
            state->enemies[index].health = 100.0f;
            state->enemies[index].fireCooldown = 0.25f + (float) index * 0.07f;
            state->enemies[index].patrolPhase = patrolPhase;
            state->enemies[index].hitTimer = 0.0f;
            return;
        }
    }
}

static void add_structure(GameState *state,
                          StructureKind kind,
                          Vec2 position,
                          Vec2 size,
                          float rotation,
                          bool blocksMovement,
                          bool blocksProjectiles,
                          bool vaultable,
                          bool conceals) {
    size_t index;
    for (index = 0; index < GAME_MAX_STRUCTURES; index += 1) {
        if (!state->structures[index].active) {
            state->structures[index].active = true;
            state->structures[index].kind = kind;
            state->structures[index].position = position;
            state->structures[index].size = size;
            state->structures[index].rotation = rotation;
            state->structures[index].blocksMovement = blocksMovement;
            state->structures[index].blocksProjectiles = blocksProjectiles;
            state->structures[index].vaultable = vaultable;
            state->structures[index].conceals = conceals;
            return;
        }
    }
}

static InventoryItem *selected_item(GameState *state) {
    if (state->player.selectedIndex < 0 || state->player.selectedIndex >= state->player.inventoryCount) {
        return NULL;
    }
    return &state->player.inventory[state->player.selectedIndex];
}

static const InventoryItem *selected_item_const(const GameState *state) {
    if (state->player.selectedIndex < 0 || state->player.selectedIndex >= state->player.inventoryCount) {
        return NULL;
    }
    return &state->player.inventory[state->player.selectedIndex];
}

static bool position_inside_structure(const Structure *structure, Vec2 position, float padding) {
    if (!structure->active) {
        return false;
    }

    return fabsf(position.x - structure->position.x) <= (structure->size.x * 0.5f + padding) &&
           fabsf(position.y - structure->position.y) <= (structure->size.y * 0.5f + padding);
}

static bool position_inside_blocking_structure(const GameState *state, Vec2 position, float radius) {
    size_t index;
    for (index = 0; index < GAME_MAX_STRUCTURES; index += 1) {
        const Structure *structure = &state->structures[index];
        if (structure->active && structure->blocksMovement && position_inside_structure(structure, position, radius)) {
            return true;
        }
    }
    return false;
}

static bool projectile_inside_cover(const GameState *state, Vec2 position) {
    size_t index;
    for (index = 0; index < GAME_MAX_STRUCTURES; index += 1) {
        const Structure *structure = &state->structures[index];
        if (structure->active && structure->blocksProjectiles && position_inside_structure(structure, position, 1.0f)) {
            return true;
        }
    }
    return false;
}

static bool player_in_concealment(const GameState *state) {
    size_t index;
    for (index = 0; index < GAME_MAX_STRUCTURES; index += 1) {
        const Structure *structure = &state->structures[index];
        if (structure->active && structure->conceals &&
            position_inside_structure(structure, state->player.position, player_radius(&state->player) + 6.0f)) {
            return true;
        }
    }
    return false;
}

static float terrain_speed_multiplier(const GameState *state, Vec2 position) {
    float multiplier = 1.0f;
    size_t index;
    for (index = 0; index < GAME_MAX_STRUCTURES; index += 1) {
        const Structure *structure = &state->structures[index];
        if (!structure->active || !position_inside_structure(structure, position, 4.0f)) {
            continue;
        }

        switch (structure->kind) {
            case StructureKind_Road:
                multiplier *= 1.08f;
                break;
            case StructureKind_TreeCluster:
                multiplier *= 0.82f;
                break;
            case StructureKind_Ridge:
                multiplier *= 0.92f;
                break;
            default:
                break;
        }
    }

    return clampf(multiplier, 0.65f, 1.15f);
}

static void clamp_player_to_world(Player *player) {
    player->position.x = clampf(player->position.x, -kWorldHalfWidth, kWorldHalfWidth);
    player->position.y = clampf(player->position.y, -kWorldHalfHeight, kWorldHalfHeight);
}

static void attempt_move_player(GameState *state, Vec2 desiredPosition) {
    Player *player = &state->player;
    float radius = player_radius(player);
    Vec2 candidate = desiredPosition;

    candidate.x = clampf(candidate.x, -kWorldHalfWidth, kWorldHalfWidth);
    candidate.y = clampf(candidate.y, -kWorldHalfHeight, kWorldHalfHeight);

    if (!position_inside_blocking_structure(state, candidate, radius)) {
        player->position = candidate;
        return;
    }

    candidate = vec2_make(desiredPosition.x, player->position.y);
    candidate.x = clampf(candidate.x, -kWorldHalfWidth, kWorldHalfWidth);
    if (!position_inside_blocking_structure(state, candidate, radius)) {
        player->position = candidate;
        return;
    }

    candidate = vec2_make(player->position.x, desiredPosition.y);
    candidate.y = clampf(candidate.y, -kWorldHalfHeight, kWorldHalfHeight);
    if (!position_inside_blocking_structure(state, candidate, radius)) {
        player->position = candidate;
    }
}

static void attempt_move_enemy(const GameState *state, Enemy *enemy, Vec2 desiredPosition) {
    Vec2 candidate = desiredPosition;
    candidate.x = clampf(candidate.x, -kWorldHalfWidth, kWorldHalfWidth);
    candidate.y = clampf(candidate.y, -kWorldHalfHeight, kWorldHalfHeight);

    if (!position_inside_blocking_structure(state, candidate, kEnemyRadius)) {
        enemy->position = candidate;
    }
}

static void spawn_projectile(GameState *state, Vec2 position, Vec2 direction, float speed, float damage, bool fromPlayer) {
    size_t index;
    for (index = 0; index < GAME_MAX_PROJECTILES; index += 1) {
        if (!state->projectiles[index].active) {
            state->projectiles[index].active = true;
            state->projectiles[index].position = position;
            state->projectiles[index].velocity = vec2_scale(vec2_normalize(direction), speed);
            state->projectiles[index].ttl = 1.85f;
            state->projectiles[index].damage = damage;
            state->projectiles[index].fromPlayer = fromPlayer;
            return;
        }
    }
}

static void reset_weapon_logic(GameState *state) {
    state->player.burstShotsRemaining = 0;
}

static bool try_apply_suppressor(GameState *state) {
    int preferred[] = {
        state->player.selectedIndex,
        state->player.primaryIndex,
        state->player.secondaryIndex
    };
    size_t slot;

    for (slot = 0; slot < sizeof(preferred) / sizeof(preferred[0]); slot += 1) {
        int index = preferred[slot];
        if (index >= 0 && index < state->player.inventoryCount) {
            InventoryItem *item = &state->player.inventory[index];
            if (item->kind == ItemKind_Gun && item->supportsSuppressor && !item->suppressed) {
                item->suppressed = true;
                return true;
            }
        }
    }
    return false;
}

static void collect_world_item(GameState *state, size_t index) {
    WorldItem *worldItem = &state->worldItems[index];
    Player *player = &state->player;
    char buffer[GAME_EVENT_LENGTH];

    if (!worldItem->active) {
        return;
    }

    switch (worldItem->kind) {
        case ItemKind_BulletBox: {
            int *reserve = ammo_reserve(player, worldItem->ammoType);
            *reserve += worldItem->quantity;
            snprintf(buffer, sizeof(buffer), "Recovered %d loose rounds.", worldItem->quantity);
            set_event(state, buffer);
            state->collectedItemCount += 1;
            break;
        }
        case ItemKind_Magazine: {
            int *reserve = ammo_reserve(player, worldItem->ammoType);
            int rounds = worldItem->quantity * worldItem->magazineCapacity;
            *reserve += rounds;
            snprintf(buffer, sizeof(buffer), "Recovered %d rounds in magazines.", rounds);
            set_event(state, buffer);
            state->collectedItemCount += 1;
            break;
        }
        case ItemKind_Attachment: {
            if (try_apply_suppressor(state)) {
                set_event(state, "Mounted suppressor on current loadout.");
            } else {
                add_inventory_item(player, make_support_item(worldItem->name, ItemKind_Attachment, AmmoType_None, 1, 0));
                set_event(state, "Stored suppressor for later.");
            }
            state->collectedItemCount += 1;
            break;
        }
        case ItemKind_Medkit: {
            player->health = clampf(player->health + 30.0f, 0.0f, 100.0f);
            set_event(state, "Applied field dressing.");
            state->collectedItemCount += 1;
            break;
        }
        case ItemKind_Objective: {
            state->objectiveCount += 1;
            snprintf(buffer, sizeof(buffer), "Objective secured: %s.", worldItem->name);
            set_event(state, buffer);
            break;
        }
        case ItemKind_Blade:
        case ItemKind_Gun: {
            InventoryItem item = make_weapon(worldItem->name,
                                             worldItem->weaponClass,
                                             worldItem->ammoType,
                                             worldItem->magazineCapacity,
                                             worldItem->roundsInMagazine,
                                             worldItem->damage,
                                             (worldItem->weaponClass == WeaponClass_Knife) ? 70.0f : 820.0f,
                                             worldItem->suppressed,
                                             worldItem->recoil,
                                             worldItem->muzzleVelocity,
                                             worldItem->fireMode,
                                             worldItem->supportedFireModes,
                                             worldItem->supportsSuppressor,
                                             worldItem->supportsOptic,
                                             worldItem->opticMounted);
            int addedIndex = add_inventory_item(player, item);
            if (addedIndex >= 0) {
                if ((worldItem->weaponClass == WeaponClass_Rifle || worldItem->weaponClass == WeaponClass_Carbine) &&
                    player->primaryIndex < 0) {
                    player->primaryIndex = addedIndex;
                } else if (worldItem->weaponClass == WeaponClass_Pistol && player->secondaryIndex < 0) {
                    player->secondaryIndex = addedIndex;
                } else if (worldItem->weaponClass == WeaponClass_Knife && player->meleeIndex < 0) {
                    player->meleeIndex = addedIndex;
                }
                snprintf(buffer, sizeof(buffer), "Collected %s.", worldItem->name);
                set_event(state, buffer);
                state->collectedItemCount += 1;
            } else {
                set_event(state, "Pack is full. Could not collect item.");
                return;
            }
            break;
        }
        case ItemKind_None:
        default:
            return;
    }

    worldItem->active = false;
}

static void collect_nearby_item(GameState *state) {
    size_t index;
    float closestDistance = kPickupRadius;
    size_t closestIndex = GAME_MAX_ITEMS;
    for (index = 0; index < GAME_MAX_ITEMS; index += 1) {
        if (!state->worldItems[index].active) {
            continue;
        }

        if (state->worldItems[index].kind == ItemKind_Objective) {
            closestDistance = kPickupRadius + 18.0f;
        }

        if (vec2_distance(state->player.position, state->worldItems[index].position) < closestDistance) {
            closestDistance = vec2_distance(state->player.position, state->worldItems[index].position);
            closestIndex = index;
        }
    }

    if (closestIndex < GAME_MAX_ITEMS) {
        collect_world_item(state, closestIndex);
    } else {
        set_event(state, "No field item close enough to recover.");
    }
}

static void reload_selected_weapon(GameState *state) {
    InventoryItem *item = selected_item(state);
    char buffer[GAME_EVENT_LENGTH];

    if (item == NULL || item->kind != ItemKind_Gun || item->weaponClass == WeaponClass_Knife) {
        set_event(state, "Select a firearm before reloading.");
        return;
    }

    if (item->roundsInMagazine >= item->magazineCapacity) {
        set_event(state, "Magazine already topped off.");
        return;
    }

    {
        int *reserve = ammo_reserve(&state->player, item->ammoType);
        int needed;
        int loaded;

        if (*reserve <= 0) {
            set_event(state, "No reserve ammunition available.");
            return;
        }

        needed = item->magazineCapacity - item->roundsInMagazine;
        loaded = (*reserve < needed) ? *reserve : needed;
        *reserve -= loaded;
        item->roundsInMagazine += loaded;
    }

    state->player.fireCooldown = 0.36f;
    snprintf(buffer, sizeof(buffer), "Reloaded %s.", item->name);
    set_event(state, buffer);
}

static void toggle_fire_mode(GameState *state) {
    InventoryItem *item = selected_item(state);
    FireMode sequence[] = {FireMode_Semi, FireMode_Burst, FireMode_Auto};
    size_t index;

    if (item == NULL || item->kind != ItemKind_Gun) {
        set_event(state, "Select a firearm to change fire modes.");
        return;
    }

    for (index = 0; index < sizeof(sequence) / sizeof(sequence[0]); index += 1) {
        FireMode candidate = sequence[(item->fireMode + 1 + (int) index) % 3];
        if ((item->supportedFireModes & fire_mode_mask(candidate)) != 0) {
            item->fireMode = candidate;
            reset_weapon_logic(state);
            {
                char buffer[GAME_EVENT_LENGTH];
                snprintf(buffer, sizeof(buffer), "%s set to %s.", item->name, fire_mode_name(item->fireMode));
                set_event(state, buffer);
            }
            return;
        }
    }

    set_event(state, "Weapon has no alternate fire modes.");
}

static void fire_selected_weapon(GameState *state) {
    InventoryItem *item = selected_item(state);
    Vec2 direction;

    if (item == NULL) {
        return;
    }

    if (item->weaponClass == WeaponClass_Knife) {
        size_t enemyIndex;
        bool hit = false;
        for (enemyIndex = 0; enemyIndex < GAME_MAX_ENEMIES; enemyIndex += 1) {
            Enemy *enemy = &state->enemies[enemyIndex];
            if (!enemy->active) {
                continue;
            }

            {
                Vec2 toEnemy = vec2_sub(enemy->position, state->player.position);
                float distance = vec2_length(toEnemy);
                Vec2 directionToEnemy = vec2_normalize(toEnemy);
                if (distance < item->range && vec2_dot(directionToEnemy, state->player.aim) > 0.2f) {
                    enemy->health -= item->damage;
                    enemy->hitTimer = 0.2f;
                    enemy->position = vec2_add(enemy->position, vec2_scale(directionToEnemy, 18.0f));
                    hit = true;
                    if (enemy->health <= 0.0f) {
                        enemy->active = false;
                        state->kills += 1;
                        set_event(state, "Blade takedown complete.");
                    } else {
                        set_event(state, "Blade strike landed.");
                    }
                    break;
                }
            }
        }
        if (!hit) {
            set_event(state, "Blade attack missed.");
        }
        state->player.fireCooldown = 0.55f;
        state->player.noiseTimer = 0.2f;
        return;
    }

    if (item->roundsInMagazine <= 0) {
        set_event(state, "Magazine empty. Reload.");
        state->player.fireCooldown = 0.16f;
        return;
    }

    direction = vec2_normalize(state->player.aim);

    {
        float stanceMultiplier = 1.0f;
        float leanPenalty = fabsf(state->player.lean) * 0.3f;
        float opticBonus = item->opticMounted ? 0.75f : 1.0f;
        float burstPenalty = (item->fireMode == FireMode_Auto) ? 1.25f : (item->fireMode == FireMode_Burst ? 1.1f : 1.0f);
        float recoilAngle;

        if (state->player.stance == Stance_Crouch) {
            stanceMultiplier = 0.72f;
        } else if (state->player.stance == Stance_Prone) {
            stanceMultiplier = 0.48f;
        }

        recoilAngle = item->recoil * stanceMultiplier * opticBonus * burstPenalty;
        recoilAngle *= (1.0f + leanPenalty);
        recoilAngle *= sinf((state->missionTime * 17.0f) + (float) state->collectedItemCount * 0.4f);
        direction = vec2_rotate(direction, recoilAngle);
    }

    item->roundsInMagazine -= 1;

    if (item->weaponClass == WeaponClass_Pistol) {
        state->player.fireCooldown = item->suppressed ? 0.24f : 0.20f;
    } else if (item->fireMode == FireMode_Auto) {
        state->player.fireCooldown = item->suppressed ? 0.10f : 0.085f;
    } else if (item->fireMode == FireMode_Burst) {
        state->player.fireCooldown = item->suppressed ? 0.08f : 0.07f;
    } else {
        state->player.fireCooldown = item->suppressed ? 0.16f : 0.12f;
    }

    spawn_projectile(state,
                     vec2_add(state->player.position, vec2_scale(direction, 25.0f)),
                     direction,
                     item->muzzleVelocity,
                     item->damage,
                     true);
    state->player.noiseTimer = item->suppressed ? 0.55f : 1.6f;
}

static void toggle_crouch(GameState *state) {
    if (state->player.stance == Stance_Crouch) {
        state->player.stance = Stance_Stand;
    } else {
        state->player.stance = Stance_Crouch;
    }
    set_event(state, (state->player.stance == Stance_Crouch) ? "Dropped to crouch." : "Returned to standing.");
}

static void toggle_prone(GameState *state) {
    if (state->player.stance == Stance_Prone) {
        state->player.stance = Stance_Stand;
        set_event(state, "Returned to standing.");
    } else {
        state->player.stance = Stance_Prone;
        set_event(state, "Dropped to prone.");
    }
}

static void try_vault(GameState *state) {
    size_t index;
    Vec2 forward = state->player.velocity;
    if (vec2_length(forward) < 0.1f) {
        forward = state->player.aim;
    }
    forward = vec2_normalize(forward);

    for (index = 0; index < GAME_MAX_STRUCTURES; index += 1) {
        Structure *structure = &state->structures[index];
        if (!structure->active || !structure->vaultable) {
            continue;
        }

        if (vec2_distance(state->player.position, structure->position) > 92.0f) {
            continue;
        }

        if (vec2_dot(vec2_normalize(vec2_sub(structure->position, state->player.position)), forward) < 0.15f) {
            continue;
        }

        {
            Vec2 landing = vec2_add(state->player.position, vec2_scale(forward, 88.0f));
            if (!position_inside_blocking_structure(state, landing, player_radius(&state->player))) {
                state->player.position = landing;
                state->player.fireCooldown = clampf(state->player.fireCooldown, 0.18f, 1.0f);
                state->player.stamina = clampf(state->player.stamina - 8.0f, 0.0f, 100.0f);
                set_event(state, "Vaulted low cover.");
                return;
            }
        }
    }

    set_event(state, "No low cover in position to vault.");
}

static void update_player(GameState *state, const InputState *input, float dt) {
    Player *player = &state->player;
    Vec2 movement = vec2_make(input->moveX, input->moveY);
    float moveLength = vec2_length(movement);
    float speed;
    bool sprinting;

    sprinting = input->wantsSprint && moveLength > 0.2f && player->stance == Stance_Stand && player->stamina > 8.0f;

    switch (player->stance) {
        case Stance_Crouch:
            speed = 138.0f;
            break;
        case Stance_Prone:
            speed = 88.0f;
            break;
        case Stance_Stand:
        default:
            speed = sprinting ? 270.0f : 180.0f;
            break;
    }

    if (moveLength > 0.001f) {
        Vec2 moveVelocity = vec2_scale(vec2_normalize(movement), speed * terrain_speed_multiplier(state, player->position));
        moveVelocity = vec2_scale(moveVelocity, 1.0f - (fabsf(input->lean) * 0.12f));
        player->velocity = moveVelocity;
        attempt_move_player(state, vec2_add(player->position, vec2_scale(player->velocity, dt)));
    } else {
        player->velocity = vec2_make(0.0f, 0.0f);
    }

    if (sprinting) {
        player->stamina = clampf(player->stamina - (24.0f * dt), 0.0f, 100.0f);
        player->noiseTimer = clampf(player->noiseTimer + (0.45f * dt), 0.0f, 2.0f);
    } else {
        player->stamina = clampf(player->stamina + (16.0f * dt), 0.0f, 100.0f);
    }

    if (fabsf(input->aimX) > 0.01f || fabsf(input->aimY) > 0.01f) {
        player->aim = vec2_normalize(vec2_make(input->aimX, input->aimY));
    }

    player->lean = clampf(input->lean, -1.0f, 1.0f);
    player->fireCooldown = clampf(player->fireCooldown - dt, 0.0f, 100.0f);
    player->hitTimer = clampf(player->hitTimer - dt, 0.0f, 10.0f);
    player->noiseTimer = clampf(player->noiseTimer - dt, 0.0f, 10.0f);
    clamp_player_to_world(player);
}

static void update_projectiles(GameState *state, float dt) {
    size_t index;
    size_t enemyIndex;

    for (index = 0; index < GAME_MAX_PROJECTILES; index += 1) {
        Projectile *projectile = &state->projectiles[index];
        if (!projectile->active) {
            continue;
        }

        projectile->position = vec2_add(projectile->position, vec2_scale(projectile->velocity, dt));
        projectile->ttl -= dt;

        if (projectile->ttl <= 0.0f ||
            fabsf(projectile->position.x) > (kWorldHalfWidth + 120.0f) ||
            fabsf(projectile->position.y) > (kWorldHalfHeight + 120.0f) ||
            projectile_inside_cover(state, projectile->position)) {
            projectile->active = false;
            continue;
        }

        if (projectile->fromPlayer) {
            for (enemyIndex = 0; enemyIndex < GAME_MAX_ENEMIES; enemyIndex += 1) {
                Enemy *enemy = &state->enemies[enemyIndex];
                if (!enemy->active) {
                    continue;
                }

                if (vec2_distance(projectile->position, enemy->position) < kEnemyRadius) {
                    Vec2 hitDirection = vec2_normalize(projectile->velocity);
                    enemy->health -= projectile->damage;
                    enemy->hitTimer = 0.24f;
                    enemy->position = vec2_add(enemy->position, vec2_scale(hitDirection, 16.0f));
                    projectile->active = false;
                    if (enemy->health <= 0.0f) {
                        enemy->active = false;
                        state->kills += 1;
                        set_event(state, "Hostile neutralized.");
                    }
                    break;
                }
            }
        } else if (vec2_distance(projectile->position, state->player.position) < player_radius(&state->player)) {
            state->player.health = clampf(state->player.health - projectile->damage, 0.0f, 100.0f);
            state->player.hitTimer = 0.32f;
            state->player.position = vec2_add(state->player.position, vec2_scale(vec2_normalize(projectile->velocity), 10.0f));
            projectile->active = false;
            set_event(state, "Taking fire.");
        }
    }
}

static void update_enemies(GameState *state, float dt) {
    size_t index;
    float detectionRange = 490.0f;

    if (state->player.stance == Stance_Crouch) {
        detectionRange *= 0.8f;
    } else if (state->player.stance == Stance_Prone) {
        detectionRange *= 0.62f;
    }
    if (player_in_concealment(state)) {
        detectionRange *= 0.72f;
    }
    if (state->player.noiseTimer > 0.0f) {
        detectionRange *= 1.35f;
    }

    for (index = 0; index < GAME_MAX_ENEMIES; index += 1) {
        Enemy *enemy = &state->enemies[index];
        Vec2 toPlayer;
        float distanceToPlayer;
        Vec2 moveDirection;

        if (!enemy->active) {
            continue;
        }

        enemy->hitTimer = clampf(enemy->hitTimer - dt, 0.0f, 10.0f);
        toPlayer = vec2_sub(state->player.position, enemy->position);
        distanceToPlayer = vec2_length(toPlayer);

        if (distanceToPlayer < detectionRange) {
            moveDirection = vec2_normalize(toPlayer);

            if (distanceToPlayer > 170.0f) {
                enemy->velocity = vec2_scale(moveDirection, 92.0f);
                attempt_move_enemy(state, enemy, vec2_add(enemy->position, vec2_scale(enemy->velocity, dt)));
            } else {
                enemy->velocity = vec2_make(0.0f, 0.0f);
            }

            enemy->fireCooldown = clampf(enemy->fireCooldown - dt, 0.0f, 100.0f);
            if (enemy->fireCooldown <= 0.0f) {
                float spread = 0.08f;
                if (state->player.stance == Stance_Prone) {
                    spread = 0.16f;
                }
                if (player_in_concealment(state)) {
                    spread += 0.08f;
                }
                spread *= sinf((state->missionTime * 1.7f) + enemy->patrolPhase);
                {
                    Vec2 aim = vec2_rotate(moveDirection, spread);
                    spawn_projectile(state,
                                     vec2_add(enemy->position, vec2_scale(aim, 18.0f)),
                                     aim,
                                     640.0f,
                                     8.0f,
                                     false);
                }
                enemy->fireCooldown = 0.95f + 0.16f * (float) index;
            }
        } else {
            float patrolAngle = state->missionTime * 0.28f + enemy->patrolPhase;
            enemy->velocity = vec2_make(cosf(patrolAngle), sinf(patrolAngle * 1.18f));
            attempt_move_enemy(state, enemy, vec2_add(enemy->position, vec2_scale(enemy->velocity, 34.0f * dt)));
        }
    }
}

static void setup_common_player(GameState *state, Vec2 startPosition) {
    Player *player = &state->player;
    player->position = startPosition;
    player->velocity = vec2_make(0.0f, 0.0f);
    player->aim = vec2_make(1.0f, 0.0f);
    player->health = 100.0f;
    player->stamina = 100.0f;
    player->lean = 0.0f;
    player->hitTimer = 0.0f;
    player->noiseTimer = 0.0f;
    player->stance = Stance_Stand;
    player->selectedIndex = -1;
    player->primaryIndex = -1;
    player->secondaryIndex = -1;
    player->meleeIndex = -1;
    player->ammo556 = 120;
    player->ammo9mm = 51;
    player->ammoShell = 0;
    player->burstShotsRemaining = 0;
    player->triggerHeldLastFrame = false;

    player->primaryIndex = add_inventory_item(player,
                                              make_weapon("MK18 Carbine",
                                                          WeaponClass_Carbine,
                                                          AmmoType_556,
                                                          30,
                                                          30,
                                                          32.0f,
                                                          780.0f,
                                                          false,
                                                          0.055f,
                                                          960.0f,
                                                          FireMode_Auto,
                                                          fire_mode_mask(FireMode_Semi) | fire_mode_mask(FireMode_Auto),
                                                          true,
                                                          true,
                                                          true));
    player->secondaryIndex = add_inventory_item(player,
                                                make_weapon("M17 Sidearm",
                                                            WeaponClass_Pistol,
                                                            AmmoType_9mm,
                                                            17,
                                                            17,
                                                            20.0f,
                                                            520.0f,
                                                            false,
                                                            0.042f,
                                                            700.0f,
                                                            FireMode_Semi,
                                                            fire_mode_mask(FireMode_Semi),
                                                            true,
                                                            false,
                                                            false));
    player->meleeIndex = add_inventory_item(player,
                                            make_weapon("Field Knife",
                                                        WeaponClass_Knife,
                                                        AmmoType_None,
                                                        0,
                                                        0,
                                                        52.0f,
                                                        70.0f,
                                                        false,
                                                        0.0f,
                                                        0.0f,
                                                        FireMode_Semi,
                                                        fire_mode_mask(FireMode_Semi),
                                                        false,
                                                        false,
                                                        false));
    player->selectedIndex = player->primaryIndex;
}

static void setup_cache_raid(GameState *state) {
    copy_name(state->missionName, sizeof(state->missionName), "Cache Raid");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Ridge approach. Hit the northern cache compound, recover the ledger and firing codes, then extract east.");
    state->objectiveTarget = 2;
    state->extractionZone = vec2_make(1050.0f, 640.0f);
    state->extractionRadius = 100.0f;
    setup_common_player(state, vec2_make(-1120.0f, -620.0f));

    add_structure(state, StructureKind_Road, vec2_make(-180.0f, -250.0f), vec2_make(1240.0f, 76.0f), 0.06f, false, false, false, false);
    add_structure(state, StructureKind_Ridge, vec2_make(-380.0f, -40.0f), vec2_make(340.0f, 160.0f), -0.12f, true, true, false, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-720.0f, -300.0f), vec2_make(210.0f, 190.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(30.0f, 120.0f), vec2_make(180.0f, 160.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Building, vec2_make(520.0f, 180.0f), vec2_make(260.0f, 180.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(520.0f, 320.0f), vec2_make(320.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(360.0f, 180.0f), vec2_make(24.0f, 220.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(680.0f, 180.0f), vec2_make(24.0f, 220.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_Tower, vec2_make(860.0f, 460.0f), vec2_make(80.0f, 80.0f), 0.0f, true, true, false, false);

    add_world_item(state, make_world_objective("Cache Ledger", vec2_make(530.0f, 180.0f)));
    add_world_item(state, make_world_objective("Firing Codes", vec2_make(860.0f, 460.0f)));
    add_world_item(state, make_world_supply("5.56 Ball", ItemKind_BulletBox, AmmoType_556, vec2_make(-860.0f, -440.0f), 30, 0, false));
    add_world_item(state, make_world_supply("STANAG Magazine", ItemKind_Magazine, AmmoType_556, vec2_make(-440.0f, -250.0f), 1, 30, false));
    add_world_item(state, make_world_supply("Threaded Suppressor", ItemKind_Attachment, AmmoType_None, vec2_make(210.0f, 20.0f), 1, 0, true));
    add_world_item(state, make_world_weapon("Recon Rifle",
                                            WeaponClass_Rifle,
                                            AmmoType_556,
                                            vec2_make(760.0f, 380.0f),
                                            20,
                                            20,
                                            42.0f,
                                            true,
                                            0.034f,
                                            1100.0f,
                                            FireMode_Semi,
                                            fire_mode_mask(FireMode_Semi),
                                            true,
                                            true,
                                            true));
    add_world_item(state, make_world_supply("Combat Gauze", ItemKind_Medkit, AmmoType_None, vec2_make(960.0f, 420.0f), 1, 0, false));

    add_enemy(state, vec2_make(-180.0f, -120.0f), 0.2f);
    add_enemy(state, vec2_make(260.0f, 140.0f), 0.9f);
    add_enemy(state, vec2_make(560.0f, 60.0f), 1.8f);
    add_enemy(state, vec2_make(780.0f, 300.0f), 2.6f);
    add_enemy(state, vec2_make(960.0f, 540.0f), 3.3f);
}

static void setup_hostage_recovery(GameState *state) {
    copy_name(state->missionName, sizeof(state->missionName), "Hostage Recovery");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Push through the village blocks, secure the captive beacon from the central safehouse, and extract south.");
    state->objectiveTarget = 1;
    state->extractionZone = vec2_make(160.0f, -760.0f);
    state->extractionRadius = 96.0f;
    setup_common_player(state, vec2_make(-980.0f, 540.0f));

    add_structure(state, StructureKind_Road, vec2_make(-120.0f, 120.0f), vec2_make(1260.0f, 94.0f), 0.0f, false, false, false, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-720.0f, 300.0f), vec2_make(220.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Building, vec2_make(-180.0f, 260.0f), vec2_make(180.0f, 120.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Building, vec2_make(120.0f, 260.0f), vec2_make(180.0f, 120.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Building, vec2_make(420.0f, 260.0f), vec2_make(220.0f, 150.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(420.0f, 420.0f), vec2_make(340.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(560.0f, 250.0f), vec2_make(24.0f, 220.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(760.0f, -40.0f), vec2_make(210.0f, 200.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Ridge, vec2_make(860.0f, -300.0f), vec2_make(280.0f, 140.0f), 0.0f, true, true, false, false);

    add_world_item(state, make_world_objective("Hostage Beacon", vec2_make(420.0f, 260.0f)));
    add_world_item(state, make_world_supply("9mm Magazine", ItemKind_Magazine, AmmoType_9mm, vec2_make(-420.0f, 180.0f), 2, 17, false));
    add_world_item(state, make_world_supply("5.56 Ball", ItemKind_BulletBox, AmmoType_556, vec2_make(80.0f, 120.0f), 30, 0, false));
    add_world_item(state, make_world_supply("Suppressor", ItemKind_Attachment, AmmoType_None, vec2_make(720.0f, 20.0f), 1, 0, true));
    add_world_item(state, make_world_weapon("VX-9 Carbine",
                                            WeaponClass_Carbine,
                                            AmmoType_556,
                                            vec2_make(860.0f, -220.0f),
                                            24,
                                            24,
                                            30.0f,
                                            false,
                                            0.060f,
                                            900.0f,
                                            FireMode_Burst,
                                            fire_mode_mask(FireMode_Semi) | fire_mode_mask(FireMode_Burst) | fire_mode_mask(FireMode_Auto),
                                            true,
                                            true,
                                            false));
    add_world_item(state, make_world_supply("Combat Gauze", ItemKind_Medkit, AmmoType_None, vec2_make(520.0f, 320.0f), 1, 0, false));

    add_enemy(state, vec2_make(-360.0f, 180.0f), 0.4f);
    add_enemy(state, vec2_make(-80.0f, 260.0f), 1.2f);
    add_enemy(state, vec2_make(220.0f, 240.0f), 2.1f);
    add_enemy(state, vec2_make(520.0f, 220.0f), 3.0f);
    add_enemy(state, vec2_make(740.0f, -60.0f), 3.7f);
    add_enemy(state, vec2_make(960.0f, -280.0f), 4.3f);
}

static void setup_recon_exfil(GameState *state) {
    copy_name(state->missionName, sizeof(state->missionName), "Recon & Exfil");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Move through the tree line, collect observation packages from the ridge and radio shack, then slip out north.");
    state->objectiveTarget = 2;
    state->extractionZone = vec2_make(-1040.0f, 700.0f);
    state->extractionRadius = 96.0f;
    setup_common_player(state, vec2_make(1060.0f, -640.0f));

    add_structure(state, StructureKind_Ridge, vec2_make(260.0f, -120.0f), vec2_make(420.0f, 150.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Ridge, vec2_make(-220.0f, 220.0f), vec2_make(460.0f, 170.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(780.0f, -360.0f), vec2_make(260.0f, 210.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(420.0f, 220.0f), vec2_make(240.0f, 200.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-620.0f, 500.0f), vec2_make(240.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Building, vec2_make(-40.0f, 420.0f), vec2_make(180.0f, 120.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(120.0f, 10.0f), vec2_make(260.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_Road, vec2_make(-520.0f, 20.0f), vec2_make(720.0f, 76.0f), -0.15f, false, false, false, false);

    add_world_item(state, make_world_objective("Observation Reel", vec2_make(260.0f, -120.0f)));
    add_world_item(state, make_world_objective("Radio Snapshot", vec2_make(-40.0f, 420.0f)));
    add_world_item(state, make_world_supply("5.56 Ball", ItemKind_BulletBox, AmmoType_556, vec2_make(720.0f, -520.0f), 30, 0, false));
    add_world_item(state, make_world_supply("9mm Magazine", ItemKind_Magazine, AmmoType_9mm, vec2_make(220.0f, -40.0f), 2, 17, false));
    add_world_item(state, make_world_weapon("Suppressed Scout Rifle",
                                            WeaponClass_Rifle,
                                            AmmoType_556,
                                            vec2_make(-180.0f, 280.0f),
                                            20,
                                            20,
                                            44.0f,
                                            true,
                                            0.030f,
                                            1120.0f,
                                            FireMode_Semi,
                                            fire_mode_mask(FireMode_Semi),
                                            true,
                                            true,
                                            true));
    add_world_item(state, make_world_supply("Combat Gauze", ItemKind_Medkit, AmmoType_None, vec2_make(-760.0f, 540.0f), 1, 0, false));
    add_world_item(state, make_world_supply("Threaded Suppressor", ItemKind_Attachment, AmmoType_None, vec2_make(420.0f, 220.0f), 1, 0, true));

    add_enemy(state, vec2_make(420.0f, -220.0f), 0.8f);
    add_enemy(state, vec2_make(180.0f, 60.0f), 1.6f);
    add_enemy(state, vec2_make(-80.0f, 380.0f), 2.4f);
    add_enemy(state, vec2_make(-420.0f, 200.0f), 3.1f);
    add_enemy(state, vec2_make(-740.0f, 540.0f), 4.0f);
}

static void setup_convoy_ambush(GameState *state) {
    copy_name(state->missionName, sizeof(state->missionName), "Convoy Ambush");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Break the roadside convoy, recover the manifest and crypto tablet, then withdraw west through the trees.");
    state->objectiveTarget = 2;
    state->extractionZone = vec2_make(-1100.0f, 140.0f);
    state->extractionRadius = 100.0f;
    setup_common_player(state, vec2_make(1040.0f, 60.0f));

    add_structure(state, StructureKind_Road, vec2_make(60.0f, 60.0f), vec2_make(1520.0f, 88.0f), 0.0f, false, false, false, false);
    add_structure(state, StructureKind_Convoy, vec2_make(300.0f, 60.0f), vec2_make(220.0f, 80.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Convoy, vec2_make(-20.0f, 60.0f), vec2_make(220.0f, 80.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(-260.0f, 220.0f), vec2_make(280.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(620.0f, -120.0f), vec2_make(260.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(860.0f, -220.0f), vec2_make(260.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-620.0f, 180.0f), vec2_make(260.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Ridge, vec2_make(-840.0f, -220.0f), vec2_make(320.0f, 180.0f), 0.0f, true, true, false, false);

    add_world_item(state, make_world_objective("Convoy Manifest", vec2_make(300.0f, 60.0f)));
    add_world_item(state, make_world_objective("Crypto Tablet", vec2_make(-20.0f, 60.0f)));
    add_world_item(state, make_world_supply("5.56 Ball", ItemKind_BulletBox, AmmoType_556, vec2_make(920.0f, -120.0f), 30, 0, false));
    add_world_item(state, make_world_supply("STANAG Magazine", ItemKind_Magazine, AmmoType_556, vec2_make(620.0f, -120.0f), 1, 30, false));
    add_world_item(state, make_world_supply("9mm Magazine", ItemKind_Magazine, AmmoType_9mm, vec2_make(-300.0f, 220.0f), 2, 17, false));
    add_world_item(state, make_world_weapon("Breaching Knife", WeaponClass_Knife, AmmoType_None, vec2_make(-720.0f, 220.0f), 0, 0, 68.0f, false, 0.0f, 0.0f, FireMode_Semi, fire_mode_mask(FireMode_Semi), false, false, false));
    add_world_item(state, make_world_supply("Combat Gauze", ItemKind_Medkit, AmmoType_None, vec2_make(-860.0f, -220.0f), 1, 0, false));

    add_enemy(state, vec2_make(520.0f, 60.0f), 0.5f);
    add_enemy(state, vec2_make(180.0f, 180.0f), 1.3f);
    add_enemy(state, vec2_make(-120.0f, -160.0f), 2.0f);
    add_enemy(state, vec2_make(-360.0f, 240.0f), 2.9f);
    add_enemy(state, vec2_make(-620.0f, 120.0f), 3.5f);
    add_enemy(state, vec2_make(-900.0f, -160.0f), 4.4f);
}

static void setup_mission(GameState *state, MissionType mission) {
    memset(state, 0, sizeof(*state));
    state->missionType = mission;
    state->objectiveCount = 0;
    state->objectiveTarget = 1;
    state->collectedItemCount = 0;
    state->kills = 0;
    state->victory = false;
    state->missionFailed = false;

    switch (mission) {
        case MissionType_HostageRecovery:
            setup_hostage_recovery(state);
            break;
        case MissionType_ReconExfil:
            setup_recon_exfil(state);
            break;
        case MissionType_ConvoyAmbush:
            setup_convoy_ambush(state);
            break;
        case MissionType_CacheRaid:
        default:
            setup_cache_raid(state);
            break;
    }

    set_event(state, state->missionBrief);
}

void game_init(GameState *state) {
    setup_mission(state, sMissionCursor);
}

void game_restart(GameState *state) {
    setup_mission(state, state->missionType);
}

void game_next_mission(GameState *state) {
    sMissionCursor = (MissionType) ((sMissionCursor + 1) % MissionType_Count);
    setup_mission(state, sMissionCursor);
}

void game_reset_input(InputState *input) {
    memset(input, 0, sizeof(*input));
}

void game_cycle_weapon(GameState *state, int direction) {
    int nextIndex;
    if (state->player.inventoryCount == 0) {
        state->player.selectedIndex = -1;
        return;
    }

    nextIndex = state->player.selectedIndex;
    if (nextIndex < 0) {
        nextIndex = 0;
    }

    nextIndex += direction;
    if (nextIndex < 0) {
        nextIndex = state->player.inventoryCount - 1;
    }
    if (nextIndex >= state->player.inventoryCount) {
        nextIndex = 0;
    }

    state->player.selectedIndex = nextIndex;
    reset_weapon_logic(state);
}

void game_select_primary(GameState *state) {
    if (state->player.primaryIndex >= 0) {
        state->player.selectedIndex = state->player.primaryIndex;
        reset_weapon_logic(state);
    }
}

void game_select_secondary(GameState *state) {
    if (state->player.secondaryIndex >= 0) {
        state->player.selectedIndex = state->player.secondaryIndex;
        reset_weapon_logic(state);
    }
}

void game_select_melee(GameState *state) {
    if (state->player.meleeIndex >= 0) {
        state->player.selectedIndex = state->player.meleeIndex;
        reset_weapon_logic(state);
    }
}

void game_update(GameState *state, const InputState *input, float dt) {
    bool shouldFire = false;
    InventoryItem *item;

    if (state->victory || state->missionFailed) {
        return;
    }

    state->missionTime += dt;
    update_player(state, input, dt);

    if (input->wantsPrimary) {
        game_select_primary(state);
    }
    if (input->wantsSecondary) {
        game_select_secondary(state);
    }
    if (input->wantsMelee) {
        game_select_melee(state);
    }
    if (input->wantsCycleNext) {
        game_cycle_weapon(state, 1);
    }
    if (input->wantsCyclePrevious) {
        game_cycle_weapon(state, -1);
    }
    if (input->wantsCrouchToggle) {
        toggle_crouch(state);
    }
    if (input->wantsProneToggle) {
        toggle_prone(state);
    }
    if (input->wantsVault) {
        try_vault(state);
    }
    if (input->wantsCollect) {
        collect_nearby_item(state);
    }
    if (input->wantsToggleFireMode) {
        toggle_fire_mode(state);
    }
    if (input->wantsReload) {
        reload_selected_weapon(state);
    }

    item = selected_item(state);
    if (item != NULL) {
        if (item->weaponClass == WeaponClass_Knife) {
            shouldFire = input->wantsFire && !state->player.triggerHeldLastFrame && state->player.fireCooldown <= 0.0f;
        } else if (item->kind == ItemKind_Gun) {
            if (item->fireMode == FireMode_Semi) {
                shouldFire = input->wantsFire && !state->player.triggerHeldLastFrame && state->player.fireCooldown <= 0.0f;
            } else if (item->fireMode == FireMode_Auto) {
                shouldFire = input->wantsFire && state->player.fireCooldown <= 0.0f;
            } else {
                if (input->wantsFire && !state->player.triggerHeldLastFrame && state->player.burstShotsRemaining <= 0) {
                    state->player.burstShotsRemaining = 3;
                }
                if (state->player.burstShotsRemaining > 0 && state->player.fireCooldown <= 0.0f) {
                    shouldFire = true;
                    state->player.burstShotsRemaining -= 1;
                }
            }
        }
    }

    if (shouldFire) {
        fire_selected_weapon(state);
    }

    state->player.triggerHeldLastFrame = input->wantsFire;

    update_projectiles(state, dt);
    update_enemies(state, dt);

    if (state->player.health <= 0.0f) {
        state->missionFailed = true;
        set_event(state, "Operator down.");
        return;
    }

    if (state->objectiveCount >= state->objectiveTarget &&
        vec2_distance(state->player.position, state->extractionZone) <= state->extractionRadius) {
        state->victory = true;
        set_event(state, "Extraction successful.");
    }
}

size_t game_collection_target(void) {
    return kCollectionTarget;
}

float game_world_half_width(void) {
    return kWorldHalfWidth;
}

float game_world_half_height(void) {
    return kWorldHalfHeight;
}

const char *game_mission_name(const GameState *state) {
    return state->missionName;
}

const char *game_mission_brief(const GameState *state) {
    return state->missionBrief;
}

int game_mission_objective_count(const GameState *state) {
    return state->objectiveCount;
}

int game_mission_objective_target(const GameState *state) {
    return state->objectiveTarget;
}

bool game_mission_ready_for_extract(const GameState *state) {
    return state->objectiveCount >= state->objectiveTarget;
}

const char *game_last_event(const GameState *state) {
    return state->lastEvent;
}

const char *game_selected_item_name(const GameState *state) {
    const InventoryItem *item = selected_item_const(state);
    if (item == NULL) {
        return "Empty Hands";
    }
    return item->name;
}

const char *game_selected_fire_mode_name(const GameState *state) {
    const InventoryItem *item = selected_item_const(state);
    if (item == NULL || item->kind != ItemKind_Gun) {
        return "Melee";
    }
    return fire_mode_name(item->fireMode);
}

const char *game_player_stance_name(const GameState *state) {
    return stance_name(state->player.stance);
}

size_t game_inventory_count(const GameState *state) {
    return (size_t) state->player.inventoryCount;
}

const InventoryItem *game_inventory_item_at(const GameState *state, size_t index) {
    if (index >= (size_t) state->player.inventoryCount) {
        return NULL;
    }
    return &state->player.inventory[index];
}

const char *game_inventory_item_name(const GameState *state, size_t index) {
    const InventoryItem *item = game_inventory_item_at(state, index);
    if (item == NULL) {
        return "";
    }
    return item->name;
}

int game_selected_inventory_index(const GameState *state) {
    return state->player.selectedIndex;
}

size_t game_world_item_count(const GameState *state) {
    size_t count = 0;
    size_t index;
    for (index = 0; index < GAME_MAX_ITEMS; index += 1) {
        if (state->worldItems[index].active) {
            count += 1;
        }
    }
    return count;
}

const WorldItem *game_world_item_at(const GameState *state, size_t index) {
    size_t count = 0;
    size_t itemIndex;
    for (itemIndex = 0; itemIndex < GAME_MAX_ITEMS; itemIndex += 1) {
        if (!state->worldItems[itemIndex].active) {
            continue;
        }
        if (count == index) {
            return &state->worldItems[itemIndex];
        }
        count += 1;
    }
    return NULL;
}

size_t game_enemy_count(const GameState *state) {
    size_t count = 0;
    size_t index;
    for (index = 0; index < GAME_MAX_ENEMIES; index += 1) {
        if (state->enemies[index].active) {
            count += 1;
        }
    }
    return count;
}

const Enemy *game_enemy_at(const GameState *state, size_t index) {
    size_t count = 0;
    size_t enemyIndex;
    for (enemyIndex = 0; enemyIndex < GAME_MAX_ENEMIES; enemyIndex += 1) {
        if (!state->enemies[enemyIndex].active) {
            continue;
        }
        if (count == index) {
            return &state->enemies[enemyIndex];
        }
        count += 1;
    }
    return NULL;
}

size_t game_projectile_count(const GameState *state) {
    size_t count = 0;
    size_t index;
    for (index = 0; index < GAME_MAX_PROJECTILES; index += 1) {
        if (state->projectiles[index].active) {
            count += 1;
        }
    }
    return count;
}

const Projectile *game_projectile_at(const GameState *state, size_t index) {
    size_t count = 0;
    size_t projectileIndex;
    for (projectileIndex = 0; projectileIndex < GAME_MAX_PROJECTILES; projectileIndex += 1) {
        if (!state->projectiles[projectileIndex].active) {
            continue;
        }
        if (count == index) {
            return &state->projectiles[projectileIndex];
        }
        count += 1;
    }
    return NULL;
}

size_t game_structure_count(const GameState *state) {
    size_t count = 0;
    size_t index;
    for (index = 0; index < GAME_MAX_STRUCTURES; index += 1) {
        if (state->structures[index].active) {
            count += 1;
        }
    }
    return count;
}

const Structure *game_structure_at(const GameState *state, size_t index) {
    size_t count = 0;
    size_t structureIndex;
    for (structureIndex = 0; structureIndex < GAME_MAX_STRUCTURES; structureIndex += 1) {
        if (!state->structures[structureIndex].active) {
            continue;
        }
        if (count == index) {
            return &state->structures[structureIndex];
        }
        count += 1;
    }
    return NULL;
}

float game_player_health(const GameState *state) {
    return state->player.health;
}

float game_player_stamina(const GameState *state) {
    return state->player.stamina;
}

float game_player_lean(const GameState *state) {
    return state->player.lean;
}

int game_player_total_ammo(const GameState *state, AmmoType ammoType) {
    switch (ammoType) {
        case AmmoType_556:
            return state->player.ammo556;
        case AmmoType_9mm:
            return state->player.ammo9mm;
        case AmmoType_Shell:
            return state->player.ammoShell;
        case AmmoType_None:
        default:
            return 0;
    }
}
