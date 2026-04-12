#include "engine.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const float kWorldHalfWidth = 1200.0f;
static const float kWorldHalfHeight = 900.0f;
static const float kPickupRadius = 70.0f;
static const float kPlayerRadius = 18.0f;
static const float kEnemyRadius = 18.0f;
static const size_t kCollectionTarget = 7;

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

static InventoryItem make_weapon(const char *name,
                                 WeaponClass weaponClass,
                                 AmmoType ammoType,
                                 int capacity,
                                 int rounds,
                                 float damage,
                                 float range,
                                 bool suppressed) {
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
                                   bool suppressed) {
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
            state->enemies[index].fireCooldown = 0.2f + (float) index * 0.1f;
            state->enemies[index].patrolPhase = patrolPhase;
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

static void clamp_player_to_world(Player *player) {
    player->position.x = clampf(player->position.x, -kWorldHalfWidth, kWorldHalfWidth);
    player->position.y = clampf(player->position.y, -kWorldHalfHeight, kWorldHalfHeight);
}

static void spawn_projectile(GameState *state, Vec2 position, Vec2 direction, float speed, float damage, bool fromPlayer) {
    size_t index;
    for (index = 0; index < GAME_MAX_PROJECTILES; index += 1) {
        if (!state->projectiles[index].active) {
            state->projectiles[index].active = true;
            state->projectiles[index].position = position;
            state->projectiles[index].velocity = vec2_scale(vec2_normalize(direction), speed);
            state->projectiles[index].ttl = 1.75f;
            state->projectiles[index].damage = damage;
            state->projectiles[index].fromPlayer = fromPlayer;
            return;
        }
    }
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
            if (item->kind == ItemKind_Gun && !item->suppressed) {
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
            break;
        }
        case ItemKind_Magazine: {
            int *reserve = ammo_reserve(player, worldItem->ammoType);
            int rounds = worldItem->quantity * worldItem->magazineCapacity;
            *reserve += rounds;
            snprintf(buffer, sizeof(buffer), "Recovered %d rounds in magazines.", rounds);
            set_event(state, buffer);
            break;
        }
        case ItemKind_Attachment: {
            if (try_apply_suppressor(state)) {
                set_event(state, "Mounted suppressor on current loadout.");
            } else {
                add_inventory_item(player, make_support_item(worldItem->name, ItemKind_Attachment, AmmoType_None, 1, 0));
                set_event(state, "Stored suppressor for later.");
            }
            break;
        }
        case ItemKind_Medkit: {
            player->health = clampf(player->health + 30.0f, 0.0f, 100.0f);
            set_event(state, "Used field dressing and recovered health.");
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
                                             (worldItem->weaponClass == WeaponClass_Knife) ? 70.0f : 700.0f,
                                             worldItem->suppressed);
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
    state->collectedItemCount += 1;
}

static void collect_nearby_item(GameState *state) {
    size_t index;
    float closestDistance = kPickupRadius;
    size_t closestIndex = GAME_MAX_ITEMS;
    for (index = 0; index < GAME_MAX_ITEMS; index += 1) {
        if (!state->worldItems[index].active) {
            continue;
        }

        float distance = vec2_distance(state->player.position, state->worldItems[index].position);
        if (distance < closestDistance) {
            closestDistance = distance;
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

    int *reserve = ammo_reserve(&state->player, item->ammoType);
    if (*reserve <= 0) {
        set_event(state, "No reserve ammunition available.");
        return;
    }

    int needed = item->magazineCapacity - item->roundsInMagazine;
    int loaded = (*reserve < needed) ? *reserve : needed;
    *reserve -= loaded;
    item->roundsInMagazine += loaded;
    state->player.fireCooldown = 0.35f;
    snprintf(buffer, sizeof(buffer), "Reloaded %s.", item->name);
    set_event(state, buffer);
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

            Vec2 toEnemy = vec2_sub(enemy->position, state->player.position);
            float distance = vec2_length(toEnemy);
            Vec2 directionToEnemy = vec2_normalize(toEnemy);
            if (distance < item->range && vec2_dot(directionToEnemy, state->player.aim) > 0.1f) {
                enemy->health -= item->damage;
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
        if (!hit) {
            set_event(state, "Blade attack missed.");
        }
        state->player.fireCooldown = 0.55f;
        return;
    }

    if (item->roundsInMagazine <= 0) {
        set_event(state, "Magazine empty. Reload.");
        state->player.fireCooldown = 0.15f;
        return;
    }

    direction = vec2_normalize(state->player.aim);
    item->roundsInMagazine -= 1;

    if (item->weaponClass == WeaponClass_Pistol) {
        state->player.fireCooldown = item->suppressed ? 0.22f : 0.18f;
        spawn_projectile(state,
                         vec2_add(state->player.position, vec2_scale(direction, 22.0f)),
                         direction,
                         720.0f,
                         item->damage,
                         true);
    } else {
        state->player.fireCooldown = item->suppressed ? 0.12f : 0.09f;
        spawn_projectile(state,
                         vec2_add(state->player.position, vec2_scale(direction, 26.0f)),
                         direction,
                         980.0f,
                         item->damage,
                         true);
    }
}

static void update_player(GameState *state, const InputState *input, float dt) {
    Player *player = &state->player;
    Vec2 movement = vec2_make(input->moveX, input->moveY);
    float moveLength = vec2_length(movement);
    bool sprinting = input->wantsSprint && moveLength > 0.2f && player->stamina > 5.0f;
    float speed = sprinting ? 255.0f : 175.0f;

    if (moveLength > 0.001f) {
        movement = vec2_scale(vec2_normalize(movement), speed);
        player->velocity = movement;
        player->position = vec2_add(player->position, vec2_scale(player->velocity, dt));
    } else {
        player->velocity = vec2_make(0.0f, 0.0f);
    }

    if (sprinting) {
        player->stamina = clampf(player->stamina - (22.0f * dt), 0.0f, 100.0f);
    } else {
        player->stamina = clampf(player->stamina + (15.0f * dt), 0.0f, 100.0f);
    }

    if (fabsf(input->aimX) > 0.01f || fabsf(input->aimY) > 0.01f) {
        player->aim = vec2_normalize(vec2_make(input->aimX, input->aimY));
    }

    player->fireCooldown = clampf(player->fireCooldown - dt, 0.0f, 100.0f);
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
            fabsf(projectile->position.x) > (kWorldHalfWidth + 100.0f) ||
            fabsf(projectile->position.y) > (kWorldHalfHeight + 100.0f)) {
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
                    enemy->health -= projectile->damage;
                    projectile->active = false;
                    if (enemy->health <= 0.0f) {
                        enemy->active = false;
                        state->kills += 1;
                        set_event(state, "Hostile neutralized.");
                    }
                    break;
                }
            }
        } else if (vec2_distance(projectile->position, state->player.position) < kPlayerRadius) {
            state->player.health = clampf(state->player.health - projectile->damage, 0.0f, 100.0f);
            projectile->active = false;
            set_event(state, "Taking fire.");
        }
    }
}

static void update_enemies(GameState *state, float dt) {
    size_t index;
    for (index = 0; index < GAME_MAX_ENEMIES; index += 1) {
        Enemy *enemy = &state->enemies[index];
        Vec2 toPlayer;
        float distanceToPlayer;
        Vec2 moveDirection;

        if (!enemy->active) {
            continue;
        }

        toPlayer = vec2_sub(state->player.position, enemy->position);
        distanceToPlayer = vec2_length(toPlayer);

        if (distanceToPlayer < 520.0f) {
            moveDirection = vec2_normalize(toPlayer);
            if (distanceToPlayer > 165.0f) {
                enemy->velocity = vec2_scale(moveDirection, 85.0f);
                enemy->position = vec2_add(enemy->position, vec2_scale(enemy->velocity, dt));
            } else {
                enemy->velocity = vec2_make(0.0f, 0.0f);
            }

            enemy->fireCooldown = clampf(enemy->fireCooldown - dt, 0.0f, 100.0f);
            if (enemy->fireCooldown <= 0.0f) {
                float spread = sinf(state->missionTime * 2.3f + enemy->patrolPhase) * 0.12f;
                Vec2 aim = vec2_rotate(moveDirection, spread);
                spawn_projectile(state,
                                 vec2_add(enemy->position, vec2_scale(aim, 18.0f)),
                                 aim,
                                 620.0f,
                                 8.0f,
                                 false);
                enemy->fireCooldown = 1.1f + 0.2f * (float) index;
            }
        } else {
            float patrolAngle = state->missionTime * 0.35f + enemy->patrolPhase;
            enemy->velocity = vec2_make(cosf(patrolAngle), sinf(patrolAngle * 1.3f));
            enemy->position = vec2_add(enemy->position, vec2_scale(enemy->velocity, 32.0f * dt));
        }

        enemy->position.x = clampf(enemy->position.x, -kWorldHalfWidth, kWorldHalfWidth);
        enemy->position.y = clampf(enemy->position.y, -kWorldHalfHeight, kWorldHalfHeight);
    }
}

void game_init(GameState *state) {
    Player *player;

    memset(state, 0, sizeof(*state));
    player = &state->player;
    player->position = vec2_make(-950.0f, -620.0f);
    player->velocity = vec2_make(0.0f, 0.0f);
    player->aim = vec2_make(1.0f, 0.0f);
    player->health = 100.0f;
    player->stamina = 100.0f;
    player->selectedIndex = -1;
    player->primaryIndex = -1;
    player->secondaryIndex = -1;
    player->meleeIndex = -1;
    player->ammo556 = 90;
    player->ammo9mm = 42;
    player->ammoShell = 0;

    player->primaryIndex = add_inventory_item(player, make_weapon("MK18 Carbine", WeaponClass_Carbine, AmmoType_556, 30, 30, 34.0f, 700.0f, false));
    player->secondaryIndex = add_inventory_item(player, make_weapon("M17 Sidearm", WeaponClass_Pistol, AmmoType_9mm, 17, 17, 22.0f, 520.0f, false));
    player->meleeIndex = add_inventory_item(player, make_weapon("Field Knife", WeaponClass_Knife, AmmoType_None, 0, 0, 50.0f, 70.0f, false));
    player->selectedIndex = player->primaryIndex;

    state->extractionZone = vec2_make(920.0f, 660.0f);
    state->extractionRadius = 95.0f;
    set_event(state, "Recover field equipment, then extract to the northeast.");

    add_world_item(state, make_world_supply("5.56 Ball", ItemKind_BulletBox, AmmoType_556, vec2_make(-780.0f, -540.0f), 30, 0, false));
    add_world_item(state, make_world_supply("STANAG Magazine", ItemKind_Magazine, AmmoType_556, vec2_make(-520.0f, -440.0f), 1, 30, false));
    add_world_item(state, make_world_supply("9mm Magazine", ItemKind_Magazine, AmmoType_9mm, vec2_make(-280.0f, -330.0f), 2, 17, false));
    add_world_item(state, make_world_supply("Threaded Suppressor", ItemKind_Attachment, AmmoType_None, vec2_make(-110.0f, -180.0f), 1, 0, true));
    add_world_item(state, make_world_weapon("Suppressed Scout Rifle", WeaponClass_Rifle, AmmoType_556, vec2_make(160.0f, -120.0f), 20, 20, 45.0f, true));
    add_world_item(state, make_world_supply("Combat Gauze", ItemKind_Medkit, AmmoType_None, vec2_make(420.0f, -10.0f), 1, 0, false));
    add_world_item(state, make_world_weapon("Breaching Knife", WeaponClass_Knife, AmmoType_None, vec2_make(540.0f, 240.0f), 0, 0, 65.0f, false));
    add_world_item(state, make_world_supply("Loose 9mm", ItemKind_BulletBox, AmmoType_9mm, vec2_make(760.0f, 360.0f), 24, 0, false));
    add_world_item(state, make_world_supply("STANAG Magazine", ItemKind_Magazine, AmmoType_556, vec2_make(820.0f, 500.0f), 1, 30, false));
    add_world_item(state, make_world_supply("Suppressor", ItemKind_Attachment, AmmoType_None, vec2_make(970.0f, 560.0f), 1, 0, true));

    add_enemy(state, vec2_make(-300.0f, -40.0f), 0.2f);
    add_enemy(state, vec2_make(80.0f, 80.0f), 1.1f);
    add_enemy(state, vec2_make(360.0f, 210.0f), 2.4f);
    add_enemy(state, vec2_make(690.0f, 430.0f), 3.6f);
    add_enemy(state, vec2_make(940.0f, 670.0f), 4.1f);
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
}

void game_select_primary(GameState *state) {
    if (state->player.primaryIndex >= 0) {
        state->player.selectedIndex = state->player.primaryIndex;
    }
}

void game_select_secondary(GameState *state) {
    if (state->player.secondaryIndex >= 0) {
        state->player.selectedIndex = state->player.secondaryIndex;
    }
}

void game_select_melee(GameState *state) {
    if (state->player.meleeIndex >= 0) {
        state->player.selectedIndex = state->player.meleeIndex;
    }
}

void game_update(GameState *state, const InputState *input, float dt) {
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
    if (input->wantsCollect) {
        collect_nearby_item(state);
    }
    if (input->wantsReload) {
        reload_selected_weapon(state);
    }
    if (input->wantsFire && state->player.fireCooldown <= 0.0f) {
        fire_selected_weapon(state);
    }

    update_projectiles(state, dt);
    update_enemies(state, dt);

    if (state->player.health <= 0.0f) {
        state->missionFailed = true;
        set_event(state, "Operator down.");
        return;
    }

    if ((size_t) state->collectedItemCount >= game_collection_target() &&
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

float game_player_health(const GameState *state) {
    return state->player.health;
}

float game_player_stamina(const GameState *state) {
    return state->player.stamina;
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

