#include "engine.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const float kWorldHalfWidth = 1400.0f;
static const float kWorldHalfHeight = 980.0f;
static const float kPickupRadius = 72.0f;
static const float kInteractRadius = 88.0f;
static const float kPlayerRadiusStand = 18.0f;
static const float kPlayerRadiusCrouch = 15.0f;
static const float kPlayerRadiusProne = 12.0f;
static const float kEnemyRadius = 18.0f;
static const size_t kCollectionTarget = 8;
static MissionType sMissionCursor = MissionType_CacheRaid;

enum {
    kMaxContentItemTemplates = 48,
    kMaxMissionLoadoutEntries = 32,
    kMaxMissionLootEntries = 96
};

typedef struct ContentItemTemplate {
    bool active;
    char identifier[32];
    ItemKind kind;
    AmmoType ammoType;
    WeaponClass weaponClass;
    char name[32];
    int quantity;
    int magazineCapacity;
    int roundsInMagazine;
    float damage;
    float range;
    bool suppressed;
    float recoil;
    float muzzleVelocity;
    FireMode fireMode;
    unsigned int supportedFireModes;
    bool supportsSuppressor;
    bool supportsOptic;
    bool opticMounted;
} ContentItemTemplate;

typedef struct MissionLoadoutEntry {
    bool active;
    MissionType missionType;
    char templateIdentifier[32];
    LoadoutSlotHint slotHint;
} MissionLoadoutEntry;

typedef struct MissionLootEntry {
    bool active;
    MissionType missionType;
    char templateIdentifier[32];
    Vec2 position;
} MissionLootEntry;

static ContentItemTemplate sContentItemTemplates[kMaxContentItemTemplates];
static MissionLoadoutEntry sMissionLoadoutEntries[kMaxMissionLoadoutEntries];
static MissionLootEntry sMissionLootEntries[kMaxMissionLootEntries];
static size_t sContentItemTemplateCount = 0;
static size_t sMissionLoadoutEntryCount = 0;
static size_t sMissionLootEntryCount = 0;

static int add_inventory_item(Player *player, InventoryItem item);
static void add_world_item(GameState *state, WorldItem item);
static void register_default_content(void);
static void ensure_content_database_loaded(void);
static int add_navigation_node(GameState *state,
                               Vec2 position,
                               float traversalCost,
                               bool offersCover,
                               bool elevated,
                               bool objectiveAnchor,
                               bool extractionAnchor);
static void add_navigation_link(GameState *state, int fromIndex, int toIndex, int doorInteractableIndex);
static int nearest_navigation_node(const GameState *state, Vec2 position);
static void update_command_route(GameState *state);
static void update_discovery(GameState *state);
static void update_radio_report(GameState *state, float dt);

static float clampf(float value, float minimum, float maximum) {
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

static int clampi(int value, int minimum, int maximum) {
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

static float default_weapon_range(WeaponClass weaponClass, float muzzleVelocity) {
    switch (weaponClass) {
        case WeaponClass_Pistol:
            return 520.0f;
        case WeaponClass_Knife:
            return 70.0f;
        case WeaponClass_Rifle:
        case WeaponClass_Carbine:
        default:
            return muzzleVelocity > 1.0f ? muzzleVelocity * 0.82f : 820.0f;
    }
}

static bool identifier_matches(const char *left, const char *right) {
    return strncmp(left, right, 32) == 0;
}

static void clear_content_database_internal(void) {
    memset(sContentItemTemplates, 0, sizeof(sContentItemTemplates));
    memset(sMissionLoadoutEntries, 0, sizeof(sMissionLoadoutEntries));
    memset(sMissionLootEntries, 0, sizeof(sMissionLootEntries));
    sContentItemTemplateCount = 0;
    sMissionLoadoutEntryCount = 0;
    sMissionLootEntryCount = 0;
}

void game_content_reset(void) {
    clear_content_database_internal();
}

bool game_content_add_item_template(const char *identifier,
                                    const char *name,
                                    ItemKind kind,
                                    AmmoType ammoType,
                                    WeaponClass weaponClass,
                                    int quantity,
                                    int magazineCapacity,
                                    int roundsInMagazine,
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
    ContentItemTemplate *itemTemplate;

    if (identifier == NULL || name == NULL || sContentItemTemplateCount >= kMaxContentItemTemplates) {
        return false;
    }

    itemTemplate = &sContentItemTemplates[sContentItemTemplateCount];
    memset(itemTemplate, 0, sizeof(*itemTemplate));
    itemTemplate->active = true;
    copy_name(itemTemplate->identifier, sizeof(itemTemplate->identifier), identifier);
    copy_name(itemTemplate->name, sizeof(itemTemplate->name), name);
    itemTemplate->kind = kind;
    itemTemplate->ammoType = ammoType;
    itemTemplate->weaponClass = weaponClass;
    itemTemplate->quantity = quantity;
    itemTemplate->magazineCapacity = magazineCapacity;
    itemTemplate->roundsInMagazine = roundsInMagazine;
    itemTemplate->damage = damage;
    itemTemplate->range = range;
    itemTemplate->suppressed = suppressed;
    itemTemplate->recoil = recoil;
    itemTemplate->muzzleVelocity = muzzleVelocity;
    itemTemplate->fireMode = fireMode;
    itemTemplate->supportedFireModes = supportedFireModes;
    itemTemplate->supportsSuppressor = supportsSuppressor;
    itemTemplate->supportsOptic = supportsOptic;
    itemTemplate->opticMounted = opticMounted;
    sContentItemTemplateCount += 1;
    return true;
}

bool game_content_add_mission_loadout_entry(MissionType missionType, const char *templateIdentifier, LoadoutSlotHint slotHint) {
    MissionLoadoutEntry *entry;

    if (templateIdentifier == NULL || sMissionLoadoutEntryCount >= kMaxMissionLoadoutEntries) {
        return false;
    }

    entry = &sMissionLoadoutEntries[sMissionLoadoutEntryCount];
    memset(entry, 0, sizeof(*entry));
    entry->active = true;
    entry->missionType = missionType;
    entry->slotHint = slotHint;
    copy_name(entry->templateIdentifier, sizeof(entry->templateIdentifier), templateIdentifier);
    sMissionLoadoutEntryCount += 1;
    return true;
}

bool game_content_add_mission_loot_entry(MissionType missionType, const char *templateIdentifier, float x, float y) {
    MissionLootEntry *entry;

    if (templateIdentifier == NULL || sMissionLootEntryCount >= kMaxMissionLootEntries) {
        return false;
    }

    entry = &sMissionLootEntries[sMissionLootEntryCount];
    memset(entry, 0, sizeof(*entry));
    entry->active = true;
    entry->missionType = missionType;
    entry->position = vec2_make(x, y);
    copy_name(entry->templateIdentifier, sizeof(entry->templateIdentifier), templateIdentifier);
    sMissionLootEntryCount += 1;
    return true;
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

static const ContentItemTemplate *find_content_item_template(const char *identifier) {
    size_t index;

    for (index = 0; index < sContentItemTemplateCount; index += 1) {
        const ContentItemTemplate *itemTemplate = &sContentItemTemplates[index];
        if (itemTemplate->active && identifier_matches(itemTemplate->identifier, identifier)) {
            return itemTemplate;
        }
    }

    return NULL;
}

static InventoryItem inventory_item_from_template(const ContentItemTemplate *itemTemplate) {
    if (itemTemplate->kind == ItemKind_Gun || itemTemplate->kind == ItemKind_Blade) {
        float range = itemTemplate->range > 0.0f
            ? itemTemplate->range
            : default_weapon_range(itemTemplate->weaponClass, itemTemplate->muzzleVelocity);

        return make_weapon(itemTemplate->name,
                           itemTemplate->weaponClass,
                           itemTemplate->ammoType,
                           itemTemplate->magazineCapacity,
                           itemTemplate->roundsInMagazine,
                           itemTemplate->damage,
                           range,
                           itemTemplate->suppressed,
                           itemTemplate->recoil,
                           itemTemplate->muzzleVelocity,
                           itemTemplate->fireMode,
                           itemTemplate->supportedFireModes,
                           itemTemplate->supportsSuppressor,
                           itemTemplate->supportsOptic,
                           itemTemplate->opticMounted);
    }

    return make_support_item(itemTemplate->name,
                             itemTemplate->kind,
                             itemTemplate->ammoType,
                             itemTemplate->quantity,
                             itemTemplate->magazineCapacity);
}

static WorldItem world_item_from_template(const ContentItemTemplate *itemTemplate, Vec2 position) {
    if (itemTemplate->kind == ItemKind_Gun || itemTemplate->kind == ItemKind_Blade) {
        return make_world_weapon(itemTemplate->name,
                                 itemTemplate->weaponClass,
                                 itemTemplate->ammoType,
                                 position,
                                 itemTemplate->magazineCapacity,
                                 itemTemplate->roundsInMagazine,
                                 itemTemplate->damage,
                                 itemTemplate->suppressed,
                                 itemTemplate->recoil,
                                 itemTemplate->muzzleVelocity,
                                 itemTemplate->fireMode,
                                 itemTemplate->supportedFireModes,
                                 itemTemplate->supportsSuppressor,
                                 itemTemplate->supportsOptic,
                                 itemTemplate->opticMounted);
    }

    if (itemTemplate->kind == ItemKind_Objective) {
        return make_world_objective(itemTemplate->name, position);
    }

    return make_world_supply(itemTemplate->name,
                             itemTemplate->kind,
                             itemTemplate->ammoType,
                             position,
                             itemTemplate->quantity,
                             itemTemplate->magazineCapacity,
                             itemTemplate->suppressed);
}

static void assign_inventory_slot(Player *player,
                                  int inventoryIndex,
                                  const ContentItemTemplate *itemTemplate,
                                  LoadoutSlotHint slotHint) {
    if (inventoryIndex < 0) {
        return;
    }

    switch (slotHint) {
        case LoadoutSlotHint_Primary:
            player->primaryIndex = inventoryIndex;
            return;
        case LoadoutSlotHint_Secondary:
            player->secondaryIndex = inventoryIndex;
            return;
        case LoadoutSlotHint_Melee:
            player->meleeIndex = inventoryIndex;
            return;
        case LoadoutSlotHint_Gear:
            return;
        case LoadoutSlotHint_Auto:
        default:
            break;
    }

    if ((itemTemplate->weaponClass == WeaponClass_Rifle || itemTemplate->weaponClass == WeaponClass_Carbine) &&
        player->primaryIndex < 0) {
        player->primaryIndex = inventoryIndex;
    } else if (itemTemplate->weaponClass == WeaponClass_Pistol && player->secondaryIndex < 0) {
        player->secondaryIndex = inventoryIndex;
    } else if (itemTemplate->weaponClass == WeaponClass_Knife && player->meleeIndex < 0) {
        player->meleeIndex = inventoryIndex;
    }
}

static void apply_mission_content(GameState *state, MissionType missionType) {
    Player *player = &state->player;
    size_t index;
    int objectiveTarget = 0;

    ensure_content_database_loaded();

    for (index = 0; index < sMissionLoadoutEntryCount; index += 1) {
        const MissionLoadoutEntry *entry = &sMissionLoadoutEntries[index];
        const ContentItemTemplate *itemTemplate;
        int inventoryIndex;

        if (!entry->active || entry->missionType != missionType) {
            continue;
        }

        itemTemplate = find_content_item_template(entry->templateIdentifier);
        if (itemTemplate == NULL) {
            continue;
        }

        inventoryIndex = add_inventory_item(player, inventory_item_from_template(itemTemplate));
        assign_inventory_slot(player, inventoryIndex, itemTemplate, entry->slotHint);
    }

    if (player->selectedIndex < 0) {
        if (player->primaryIndex >= 0) {
            player->selectedIndex = player->primaryIndex;
        } else if (player->secondaryIndex >= 0) {
            player->selectedIndex = player->secondaryIndex;
        } else if (player->meleeIndex >= 0) {
            player->selectedIndex = player->meleeIndex;
        } else if (player->inventoryCount > 0) {
            player->selectedIndex = 0;
        }
    }

    for (index = 0; index < sMissionLootEntryCount; index += 1) {
        const MissionLootEntry *entry = &sMissionLootEntries[index];
        const ContentItemTemplate *itemTemplate;

        if (!entry->active || entry->missionType != missionType) {
            continue;
        }

        itemTemplate = find_content_item_template(entry->templateIdentifier);
        if (itemTemplate == NULL) {
            continue;
        }

        add_world_item(state, world_item_from_template(itemTemplate, entry->position));
        if (itemTemplate->kind == ItemKind_Objective) {
            objectiveTarget += 1;
        }
    }

    if (objectiveTarget > 0) {
        state->objectiveTarget = objectiveTarget;
    }
}

static int add_navigation_node(GameState *state,
                               Vec2 position,
                               float traversalCost,
                               bool offersCover,
                               bool elevated,
                               bool objectiveAnchor,
                               bool extractionAnchor) {
    size_t index;

    for (index = 0; index < GAME_MAX_NAV_NODES; index += 1) {
        if (!state->navigationNodes[index].active) {
            NavigationNode *node = &state->navigationNodes[index];
            size_t linkIndex;

            memset(node, 0, sizeof(*node));
            node->active = true;
            node->position = position;
            node->traversalCost = traversalCost;
            node->offersCover = offersCover;
            node->elevated = elevated;
            node->objectiveAnchor = objectiveAnchor;
            node->extractionAnchor = extractionAnchor;
            node->linkCount = 0;

            for (linkIndex = 0; linkIndex < GAME_MAX_NAV_LINKS; linkIndex += 1) {
                node->links[linkIndex] = -1;
                node->doorInteractableIndices[linkIndex] = -1;
            }

            return (int) index;
        }
    }

    return -1;
}

static void add_navigation_edge_one_way(GameState *state, int fromIndex, int toIndex, int doorInteractableIndex) {
    NavigationNode *node;
    int slot;

    if (fromIndex < 0 || fromIndex >= GAME_MAX_NAV_NODES || toIndex < 0 || toIndex >= GAME_MAX_NAV_NODES) {
        return;
    }

    node = &state->navigationNodes[fromIndex];
    if (!node->active) {
        return;
    }

    for (slot = 0; slot < node->linkCount; slot += 1) {
        if (node->links[slot] == toIndex) {
            node->doorInteractableIndices[slot] = doorInteractableIndex;
            return;
        }
    }

    if (node->linkCount >= GAME_MAX_NAV_LINKS) {
        return;
    }

    node->links[node->linkCount] = toIndex;
    node->doorInteractableIndices[node->linkCount] = doorInteractableIndex;
    node->linkCount += 1;
}

static void add_navigation_link(GameState *state, int fromIndex, int toIndex, int doorInteractableIndex) {
    add_navigation_edge_one_way(state, fromIndex, toIndex, doorInteractableIndex);
    add_navigation_edge_one_way(state, toIndex, fromIndex, doorInteractableIndex);
}

static bool navigation_link_is_open(const GameState *state, const NavigationNode *node, int linkIndex) {
    int doorIndex;

    if (linkIndex < 0 || linkIndex >= node->linkCount) {
        return false;
    }

    doorIndex = node->doorInteractableIndices[linkIndex];
    if (doorIndex < 0) {
        return true;
    }
    if (doorIndex >= GAME_MAX_INTERACTABLES) {
        return false;
    }
    if (!state->interactables[doorIndex].active) {
        return true;
    }
    return state->interactables[doorIndex].toggled;
}

static int nearest_navigation_node(const GameState *state, Vec2 position) {
    size_t index;
    int bestIndex = -1;
    float bestDistance = 1000000.0f;

    for (index = 0; index < GAME_MAX_NAV_NODES; index += 1) {
        float distance;
        const NavigationNode *node = &state->navigationNodes[index];

        if (!node->active) {
            continue;
        }

        distance = vec2_distance(position, node->position);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = (int) index;
        }
    }

    return bestIndex;
}

static Vec2 current_command_target_position(const GameState *state) {
    size_t index;

    if (state->objectiveCount >= state->objectiveTarget) {
        return state->extractionZone;
    }

    for (index = 0; index < GAME_MAX_ITEMS; index += 1) {
        const WorldItem *item = &state->worldItems[index];
        if (item->active && item->kind == ItemKind_Objective) {
            return item->position;
        }
    }

    return state->extractionZone;
}

static void update_command_route(GameState *state) {
    int startIndex;
    int targetIndex;
    Vec2 targetPosition;
    float distanceCost[GAME_MAX_NAV_NODES];
    int previousNode[GAME_MAX_NAV_NODES];
    bool visited[GAME_MAX_NAV_NODES];
    int pathStack[GAME_MAX_NAV_NODES];
    int pathCount = 0;
    int currentIndex;
    bool reachedTarget = true;
    size_t index;

    state->commandRouteCount = 0;

    targetPosition = current_command_target_position(state);
    startIndex = nearest_navigation_node(state, state->player.position);
    targetIndex = nearest_navigation_node(state, targetPosition);

    if (startIndex < 0 || targetIndex < 0) {
        state->commandRoutePoints[0] = state->player.position;
        state->commandRoutePoints[1] = targetPosition;
        state->commandRouteCount = 2;
        return;
    }

    for (index = 0; index < GAME_MAX_NAV_NODES; index += 1) {
        distanceCost[index] = 1000000.0f;
        previousNode[index] = -1;
        visited[index] = false;
    }
    distanceCost[startIndex] = 0.0f;

    for (;;) {
        size_t nodeIndex;
        float bestScore = 1000000.0f;
        currentIndex = -1;

        for (nodeIndex = 0; nodeIndex < GAME_MAX_NAV_NODES; nodeIndex += 1) {
            if (!state->navigationNodes[nodeIndex].active || visited[nodeIndex]) {
                continue;
            }
            if (distanceCost[nodeIndex] < bestScore) {
                bestScore = distanceCost[nodeIndex];
                currentIndex = (int) nodeIndex;
            }
        }

        if (currentIndex < 0 || currentIndex == targetIndex) {
            break;
        }

        visited[currentIndex] = true;

        {
            NavigationNode *node = &state->navigationNodes[currentIndex];
            int linkSlot;
            for (linkSlot = 0; linkSlot < node->linkCount; linkSlot += 1) {
                int nextIndex = node->links[linkSlot];
                NavigationNode *nextNode;
                float segmentCost;

                if (nextIndex < 0 || nextIndex >= GAME_MAX_NAV_NODES || !navigation_link_is_open(state, node, linkSlot)) {
                    continue;
                }

                nextNode = &state->navigationNodes[nextIndex];
                if (!nextNode->active) {
                    continue;
                }

                segmentCost = vec2_distance(node->position, nextNode->position);
                segmentCost *= (node->traversalCost + nextNode->traversalCost) * 0.5f;
                if (nextNode->offersCover) {
                    segmentCost *= 0.92f;
                }
                if (nextNode->elevated) {
                    segmentCost *= 1.04f;
                }

                if (distanceCost[currentIndex] + segmentCost < distanceCost[nextIndex]) {
                    distanceCost[nextIndex] = distanceCost[currentIndex] + segmentCost;
                    previousNode[nextIndex] = currentIndex;
                }
            }
        }
    }

    if (startIndex != targetIndex && previousNode[targetIndex] < 0) {
        int fallbackIndex = -1;
        float fallbackDistance = 1000000.0f;

        reachedTarget = false;
        for (index = 0; index < GAME_MAX_NAV_NODES; index += 1) {
            float candidateDistance;
            if (!state->navigationNodes[index].active || distanceCost[index] >= 999999.0f) {
                continue;
            }

            candidateDistance = vec2_distance(state->navigationNodes[index].position, targetPosition);
            if (candidateDistance < fallbackDistance) {
                fallbackDistance = candidateDistance;
                fallbackIndex = (int) index;
            }
        }

        if (fallbackIndex < 0) {
            state->commandRoutePoints[0] = state->player.position;
            state->commandRoutePoints[1] = targetPosition;
            state->commandRouteCount = 2;
            return;
        }

        targetIndex = fallbackIndex;
    }

    currentIndex = targetIndex;
    while (currentIndex >= 0 && pathCount < GAME_MAX_NAV_NODES) {
        pathStack[pathCount] = currentIndex;
        pathCount += 1;
        if (currentIndex == startIndex) {
            break;
        }
        currentIndex = previousNode[currentIndex];
    }

    state->commandRoutePoints[state->commandRouteCount] = state->player.position;
    state->commandRouteCount += 1;

    while (pathCount > 0 && state->commandRouteCount < GAME_MAX_COMMAND_ROUTE_POINTS - 1) {
        pathCount -= 1;
        state->commandRoutePoints[state->commandRouteCount] = state->navigationNodes[pathStack[pathCount]].position;
        state->commandRouteCount += 1;
    }

    if (reachedTarget && state->commandRouteCount < GAME_MAX_COMMAND_ROUTE_POINTS) {
        state->commandRoutePoints[state->commandRouteCount] = targetPosition;
        state->commandRouteCount += 1;
    }
}

static void update_discovery(GameState *state) {
    size_t index;
    const float worldItemDiscoveryRadius = 220.0f;
    const float interactableDiscoveryRadius = 240.0f;

    for (index = 0; index < GAME_MAX_ITEMS; index += 1) {
        WorldItem *item = &state->worldItems[index];
        if (!item->active || item->discovered) {
            continue;
        }

        if (vec2_distance(state->player.position, item->position) <= worldItemDiscoveryRadius) {
            item->discovered = true;
        }
    }

    for (index = 0; index < GAME_MAX_INTERACTABLES; index += 1) {
        Interactable *interactable = &state->interactables[index];
        if (!interactable->active || interactable->discovered) {
            continue;
        }

        if (vec2_distance(state->player.position, interactable->position) <= interactableDiscoveryRadius) {
            interactable->discovered = true;
        }
    }
}

static void grid_reference_for_position(Vec2 position, char *buffer, size_t bufferSize) {
    int column = clampi((int) floorf(((position.x + kWorldHalfWidth) / (kWorldHalfWidth * 2.0f)) * (float) GAME_TERRAIN_COLUMNS),
                        0,
                        GAME_TERRAIN_COLUMNS - 1);
    int row = clampi((int) floorf(((position.y + kWorldHalfHeight) / (kWorldHalfHeight * 2.0f)) * (float) GAME_TERRAIN_ROWS),
                     0,
                     GAME_TERRAIN_ROWS - 1);
    snprintf(buffer, bufferSize, "%c%d", 'A' + column, row + 1);
}

static int choose_patrol_target_node(const GameState *state, int currentNodeIndex, size_t enemyIndex, float patrolPhase) {
    const NavigationNode *node;
    int candidates[GAME_MAX_NAV_LINKS];
    int candidateCount = 0;
    int linkSlot;

    if (currentNodeIndex < 0 || currentNodeIndex >= GAME_MAX_NAV_NODES) {
        return -1;
    }

    node = &state->navigationNodes[currentNodeIndex];
    if (!node->active) {
        return -1;
    }

    for (linkSlot = 0; linkSlot < node->linkCount; linkSlot += 1) {
        if (node->links[linkSlot] >= 0 && navigation_link_is_open(state, node, linkSlot)) {
            candidates[candidateCount] = node->links[linkSlot];
            candidateCount += 1;
        }
    }

    if (candidateCount == 0) {
        return -1;
    }

    return candidates[((int) floorf(state->missionTime * 0.18f + patrolPhase * 7.0f) + (int) enemyIndex) % candidateCount];
}

static void update_radio_report(GameState *state, float dt) {
    char fromGrid[8];
    char toGrid[8];
    Enemy *reportEnemy = NULL;
    size_t index;

    state->radioReportCooldown = clampf(state->radioReportCooldown - dt, 0.0f, 600.0f);

    if (!state->radioIntelUnlocked) {
        copy_name(state->radioReport, sizeof(state->radioReport), "Command net quiet. Recover a radio to pull hostile traffic.");
        return;
    }

    if (state->radioReportCooldown > 0.0f) {
        return;
    }

    for (index = 0; index < GAME_MAX_ENEMIES; index += 1) {
        if (state->enemies[index].active) {
            reportEnemy = &state->enemies[index];
            break;
        }
    }

    if (reportEnemy == NULL) {
        copy_name(state->radioReport, sizeof(state->radioReport), "Command net clear. No hostile transmitters are active.");
        state->radioReportCooldown = 5.0f;
        return;
    }

    grid_reference_for_position(reportEnemy->position, fromGrid, sizeof(fromGrid));
    if (reportEnemy->targetNavNode >= 0 && reportEnemy->targetNavNode < GAME_MAX_NAV_NODES &&
        state->navigationNodes[reportEnemy->targetNavNode].active) {
        grid_reference_for_position(state->navigationNodes[reportEnemy->targetNavNode].position, toGrid, sizeof(toGrid));
        snprintf(state->radioReport,
                 sizeof(state->radioReport),
                 "Intercept: patrol shifting from %s toward %s.",
                 fromGrid,
                 toGrid);
    } else {
        snprintf(state->radioReport,
                 sizeof(state->radioReport),
                 "Intercept: hostile chatter centered on sector %s.",
                 fromGrid);
    }

    state->radioReportCooldown = 6.0f;
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
            item.discovered = false;
            state->worldItems[index] = item;
            return;
        }
    }
}

static float terrain_tile_width(void) {
    return (kWorldHalfWidth * 2.0f) / (float) GAME_TERRAIN_COLUMNS;
}

static float terrain_tile_height(void) {
    return (kWorldHalfHeight * 2.0f) / (float) GAME_TERRAIN_ROWS;
}

static size_t terrain_tile_index(int column, int row) {
    return (size_t) row * (size_t) GAME_TERRAIN_COLUMNS + (size_t) column;
}

static float terrain_navigation_cost(TerrainMaterial material) {
    switch (material) {
        case TerrainMaterial_Road:
            return 0.84f;
        case TerrainMaterial_Mud:
            return 1.28f;
        case TerrainMaterial_Rock:
            return 1.08f;
        case TerrainMaterial_Compound:
            return 0.95f;
        case TerrainMaterial_Forest:
            return 1.18f;
        case TerrainMaterial_Grass:
        default:
            return 1.0f;
    }
}

static bool terrain_conceals(TerrainMaterial material) {
    return material == TerrainMaterial_Forest;
}

static void initialize_terrain(GameState *state, MissionType missionType) {
    float width = terrain_tile_width();
    float height = terrain_tile_height();
    int row;
    int column;

    for (row = 0; row < GAME_TERRAIN_ROWS; row += 1) {
        for (column = 0; column < GAME_TERRAIN_COLUMNS; column += 1) {
            TerrainTile *tile = &state->terrainTiles[terrain_tile_index(column, row)];
            float undulation = sinf((float) column * 0.72f + (float) missionType * 0.33f) * 16.0f;
            undulation += cosf((float) row * 0.58f - (float) missionType * 0.27f) * 12.0f;

            memset(tile, 0, sizeof(*tile));
            tile->active = true;
            tile->position = vec2_make(-kWorldHalfWidth + width * ((float) column + 0.5f),
                                       -kWorldHalfHeight + height * ((float) row + 0.5f));
            tile->size = vec2_make(width, height);
            tile->height = undulation;
            tile->material = TerrainMaterial_Grass;
            tile->navigationCost = terrain_navigation_cost(tile->material);
            tile->conceals = terrain_conceals(tile->material);
        }
    }
}

static void paint_terrain_rect(GameState *state,
                               Vec2 position,
                               Vec2 size,
                               TerrainMaterial material,
                               float heightOffset,
                               bool forceConcealment) {
    int row;
    int column;
    float left = position.x - size.x * 0.5f;
    float right = position.x + size.x * 0.5f;
    float bottom = position.y - size.y * 0.5f;
    float top = position.y + size.y * 0.5f;

    for (row = 0; row < GAME_TERRAIN_ROWS; row += 1) {
        for (column = 0; column < GAME_TERRAIN_COLUMNS; column += 1) {
            TerrainTile *tile = &state->terrainTiles[terrain_tile_index(column, row)];
            float tileLeft = tile->position.x - tile->size.x * 0.5f;
            float tileRight = tile->position.x + tile->size.x * 0.5f;
            float tileBottom = tile->position.y - tile->size.y * 0.5f;
            float tileTop = tile->position.y + tile->size.y * 0.5f;

            if (tileRight < left || tileLeft > right || tileTop < bottom || tileBottom > top) {
                continue;
            }

            tile->material = material;
            tile->navigationCost = terrain_navigation_cost(material);
            tile->height += heightOffset;
            tile->conceals = forceConcealment || terrain_conceals(material);
        }
    }
}

static const TerrainTile *terrain_tile_at_position(const GameState *state, Vec2 position) {
    int column;
    int row;

    if (position.x < -kWorldHalfWidth || position.x > kWorldHalfWidth ||
        position.y < -kWorldHalfHeight || position.y > kWorldHalfHeight) {
        return NULL;
    }

    column = clampi((int) floorf(((position.x + kWorldHalfWidth) / (kWorldHalfWidth * 2.0f)) * (float) GAME_TERRAIN_COLUMNS),
                    0,
                    GAME_TERRAIN_COLUMNS - 1);
    row = clampi((int) floorf(((position.y + kWorldHalfHeight) / (kWorldHalfHeight * 2.0f)) * (float) GAME_TERRAIN_ROWS),
                 0,
                 GAME_TERRAIN_ROWS - 1);

    return &state->terrainTiles[terrain_tile_index(column, row)];
}

static float terrain_height_at_position(const GameState *state, Vec2 position) {
    const TerrainTile *tile = terrain_tile_at_position(state, position);
    if (tile == NULL) {
        return 0.0f;
    }
    return tile->height;
}

static int add_structure(GameState *state,
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
            Structure *structure = &state->structures[index];
            structure->active = true;
            structure->kind = kind;
            structure->position = position;
            structure->size = size;
            structure->rotation = rotation;
            structure->blocksMovement = blocksMovement;
            structure->blocksProjectiles = blocksProjectiles;
            structure->vaultable = vaultable;
            structure->conceals = conceals;

            switch (kind) {
                case StructureKind_Road:
                    paint_terrain_rect(state, position, vec2_make(size.x + 40.0f, size.y + 20.0f), TerrainMaterial_Road, -4.0f, false);
                    break;
                case StructureKind_Ridge:
                    paint_terrain_rect(state, position, vec2_make(size.x + 30.0f, size.y + 30.0f), TerrainMaterial_Rock, 18.0f, false);
                    break;
                case StructureKind_TreeCluster:
                    paint_terrain_rect(state, position, vec2_make(size.x + 50.0f, size.y + 50.0f), TerrainMaterial_Forest, 6.0f, true);
                    break;
                case StructureKind_Building:
                case StructureKind_LowWall:
                case StructureKind_Tower:
                case StructureKind_Convoy:
                    paint_terrain_rect(state, position, vec2_make(size.x + 24.0f, size.y + 24.0f), TerrainMaterial_Compound, 4.0f, false);
                    break;
                case StructureKind_Door:
                case StructureKind_None:
                default:
                    break;
            }

            return (int) index;
        }
    }

    return -1;
}

static int add_interactable(GameState *state,
                            InteractableKind kind,
                            Vec2 position,
                            Vec2 size,
                            float rotation,
                            int linkedStructureIndex,
                            bool toggled,
                            bool singleUse,
                            float cooldown,
                            int ammo556,
                            int ammo9mm,
                            int healthValue,
                            const char *name) {
    size_t index;
    for (index = 0; index < GAME_MAX_INTERACTABLES; index += 1) {
        if (!state->interactables[index].active) {
            Interactable *interactable = &state->interactables[index];
            memset(interactable, 0, sizeof(*interactable));
            interactable->active = true;
            interactable->discovered = false;
            interactable->kind = kind;
            interactable->position = position;
            interactable->size = size;
            interactable->rotation = rotation;
            interactable->linkedStructureIndex = linkedStructureIndex;
            interactable->toggled = toggled;
            interactable->singleUse = singleUse;
            interactable->cooldown = cooldown;
            interactable->ammo556 = ammo556;
            interactable->ammo9mm = ammo9mm;
            interactable->healthValue = healthValue;
            copy_name(interactable->name, sizeof(interactable->name), name);
            return (int) index;
        }
    }

    return -1;
}

static int add_gate(GameState *state, Vec2 position, bool vertical, const char *name) {
    Vec2 size = vertical ? vec2_make(18.0f, 72.0f) : vec2_make(72.0f, 18.0f);
    int structureIndex = add_structure(state, StructureKind_Door, position, size, 0.0f, true, true, false, false);
    return add_interactable(state, InteractableKind_Door, position, size, 0.0f, structureIndex, false, false, 0.0f, 0, 0, 0, name);
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
            state->enemies[index].currentNavNode = nearest_navigation_node(state, position);
            state->enemies[index].targetNavNode = -1;
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
    const TerrainTile *tile = terrain_tile_at_position(state, state->player.position);

    if (tile != NULL && tile->conceals) {
        return true;
    }

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
    const TerrainTile *tile = terrain_tile_at_position(state, position);
    float multiplier = 1.0f;

    if (tile != NULL) {
        multiplier *= 1.0f / clampf(tile->navigationCost, 0.7f, 1.5f);
    }

    return clampf(multiplier, 0.62f, 1.2f);
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
                                             default_weapon_range(worldItem->weaponClass, worldItem->muzzleVelocity),
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

static void sync_door_structure(GameState *state, const Interactable *interactable) {
    if (interactable->linkedStructureIndex < 0 || interactable->linkedStructureIndex >= GAME_MAX_STRUCTURES) {
        return;
    }

    state->structures[interactable->linkedStructureIndex].blocksMovement = !interactable->toggled;
    state->structures[interactable->linkedStructureIndex].blocksProjectiles = !interactable->toggled;
}

static bool interactable_is_spent(const Interactable *interactable) {
    return interactable->singleUse && interactable->toggled;
}

static void interact_with_supply_crate(GameState *state, Interactable *interactable) {
    char buffer[GAME_EVENT_LENGTH];

    if (interactable_is_spent(interactable)) {
        set_event(state, "Supply crate is already stripped.");
        return;
    }
    if (interactable->cooldown > 0.0f) {
        set_event(state, "Supply crate is not ready to access again.");
        return;
    }

    state->player.ammo556 += interactable->ammo556;
    state->player.ammo9mm += interactable->ammo9mm;
    state->player.health = clampf(state->player.health + (float) interactable->healthValue, 0.0f, 100.0f);
    state->collectedItemCount += 1;

    snprintf(buffer,
             sizeof(buffer),
             "Resupplied from %s: +%d 5.56, +%d 9mm, +%d health.",
             interactable->name,
             interactable->ammo556,
             interactable->ammo9mm,
             interactable->healthValue);
    set_event(state, buffer);

    if (interactable->singleUse) {
        interactable->toggled = true;
    } else {
        interactable->cooldown = 12.0f;
    }
}

static void interact_with_dead_drop(GameState *state, Interactable *interactable) {
    char buffer[GAME_EVENT_LENGTH];

    if (interactable_is_spent(interactable)) {
        set_event(state, "Dead drop already recovered.");
        return;
    }

    state->player.ammo556 += interactable->ammo556;
    state->player.ammo9mm += interactable->ammo9mm;
    state->player.health = clampf(state->player.health + (float) interactable->healthValue, 0.0f, 100.0f);
    state->collectedItemCount += 1;
    interactable->toggled = true;

    snprintf(buffer, sizeof(buffer), "Recovered %s from the dead drop.", interactable->name);
    set_event(state, buffer);
}

static void interact_with_radio(GameState *state, Interactable *interactable) {
    if (interactable_is_spent(interactable) || state->radioIntelUnlocked) {
        set_event(state, "Radio intercept is already copied.");
        interactable->toggled = true;
        return;
    }

    state->radioIntelUnlocked = true;
    interactable->toggled = true;
    interactable->discovered = true;
    state->collectedItemCount += 1;
    state->radioReportCooldown = 0.0f;
    set_event(state, "Radio intercept decoded. Hostile positions marked on the tactical map.");
}

static Enemy *nearest_enemy_to_position(GameState *state, Vec2 position, float maxDistance) {
    size_t index;
    float closestDistance = maxDistance;
    Enemy *closestEnemy = NULL;

    for (index = 0; index < GAME_MAX_ENEMIES; index += 1) {
        Enemy *enemy = &state->enemies[index];
        float distance;

        if (!enemy->active) {
            continue;
        }

        distance = vec2_distance(position, enemy->position);
        if (distance < closestDistance) {
            closestDistance = distance;
            closestEnemy = enemy;
        }
    }

    return closestEnemy;
}

static void interact_with_emplaced_weapon(GameState *state, Interactable *interactable) {
    Enemy *enemy;
    Vec2 direction;

    if (interactable->cooldown > 0.0f) {
        set_event(state, "Emplaced weapon is still settling from the last burst.");
        return;
    }

    enemy = nearest_enemy_to_position(state, interactable->position, 620.0f);
    if (enemy == NULL) {
        set_event(state, "No hostile in arc for the emplaced weapon.");
        return;
    }

    direction = vec2_normalize(vec2_sub(enemy->position, interactable->position));
    spawn_projectile(state, interactable->position, vec2_rotate(direction, -0.025f), 1180.0f, 28.0f, true);
    spawn_projectile(state, interactable->position, direction, 1220.0f, 30.0f, true);
    spawn_projectile(state, interactable->position, vec2_rotate(direction, 0.025f), 1180.0f, 28.0f, true);
    interactable->cooldown = 4.0f;
    state->player.noiseTimer = 1.9f;
    set_event(state, "Emplaced weapon stitched rounds across the patrol.");
}

static void interact_with_interactable(GameState *state, size_t index) {
    Interactable *interactable = &state->interactables[index];
    char buffer[GAME_EVENT_LENGTH];

    if (!interactable->active) {
        return;
    }

    interactable->discovered = true;

    switch (interactable->kind) {
        case InteractableKind_Door:
            if (interactable->cooldown > 0.0f) {
                return;
            }
            interactable->toggled = !interactable->toggled;
            interactable->cooldown = 0.2f;
            sync_door_structure(state, interactable);
            snprintf(buffer, sizeof(buffer), "%s %s.", interactable->name, interactable->toggled ? "opened" : "closed");
            set_event(state, buffer);
            break;
        case InteractableKind_SupplyCrate:
            interact_with_supply_crate(state, interactable);
            break;
        case InteractableKind_DeadDrop:
            interact_with_dead_drop(state, interactable);
            break;
        case InteractableKind_Radio:
            interact_with_radio(state, interactable);
            break;
        case InteractableKind_EmplacedWeapon:
            interact_with_emplaced_weapon(state, interactable);
            break;
        case InteractableKind_None:
        default:
            break;
    }
}

static void interact_nearby(GameState *state) {
    size_t worldIndex;
    size_t interactableIndex;
    size_t closestWorldIndex = GAME_MAX_ITEMS;
    size_t closestInteractableIndex = GAME_MAX_INTERACTABLES;
    float closestWorldDistance = kPickupRadius;
    float closestInteractableDistance = kInteractRadius;

    for (worldIndex = 0; worldIndex < GAME_MAX_ITEMS; worldIndex += 1) {
        float maxDistance;
        float distance;

        if (!state->worldItems[worldIndex].active) {
            continue;
        }

        maxDistance = (state->worldItems[worldIndex].kind == ItemKind_Objective) ? (kPickupRadius + 18.0f) : kPickupRadius;
        distance = vec2_distance(state->player.position, state->worldItems[worldIndex].position);
        if (distance < maxDistance && distance < closestWorldDistance) {
            closestWorldDistance = distance;
            closestWorldIndex = worldIndex;
        }
    }

    for (interactableIndex = 0; interactableIndex < GAME_MAX_INTERACTABLES; interactableIndex += 1) {
        float distance;
        if (!state->interactables[interactableIndex].active) {
            continue;
        }

        distance = vec2_distance(state->player.position, state->interactables[interactableIndex].position);
        if (distance < closestInteractableDistance) {
            closestInteractableDistance = distance;
            closestInteractableIndex = interactableIndex;
        }
    }

    if (closestInteractableIndex < GAME_MAX_INTERACTABLES &&
        (closestWorldIndex >= GAME_MAX_ITEMS || closestInteractableDistance <= closestWorldDistance + 6.0f)) {
        interact_with_interactable(state, closestInteractableIndex);
    } else if (closestWorldIndex < GAME_MAX_ITEMS) {
        collect_world_item(state, closestWorldIndex);
    } else {
        set_event(state, "No field item or interactable close enough.");
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

static void update_interactables(GameState *state, float dt) {
    size_t index;
    for (index = 0; index < GAME_MAX_INTERACTABLES; index += 1) {
        Interactable *interactable = &state->interactables[index];
        if (!interactable->active) {
            continue;
        }
        interactable->cooldown = clampf(interactable->cooldown - dt, 0.0f, 600.0f);
    }
}

static void update_enemies(GameState *state, float dt) {
    size_t index;
    float detectionRange = 490.0f;
    float playerHeight = terrain_height_at_position(state, state->player.position);

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
        float enemyDetectionRange = detectionRange;
        float enemyHeight;

        if (!enemy->active) {
            continue;
        }

        enemyHeight = terrain_height_at_position(state, enemy->position);
        if (playerHeight > enemyHeight + 8.0f) {
            enemyDetectionRange *= 1.08f;
        }

        enemy->hitTimer = clampf(enemy->hitTimer - dt, 0.0f, 10.0f);
        toPlayer = vec2_sub(state->player.position, enemy->position);
        distanceToPlayer = vec2_length(toPlayer);

        if (distanceToPlayer < enemyDetectionRange) {
            moveDirection = vec2_normalize(toPlayer);
            enemy->currentNavNode = nearest_navigation_node(state, enemy->position);
            enemy->targetNavNode = nearest_navigation_node(state, state->player.position);

            if (distanceToPlayer > 170.0f) {
                float terrainMultiplier = terrain_speed_multiplier(state, enemy->position);
                enemy->velocity = vec2_scale(moveDirection, 92.0f * terrainMultiplier);
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
            if (enemy->currentNavNode < 0) {
                enemy->currentNavNode = nearest_navigation_node(state, enemy->position);
            }

            if (enemy->currentNavNode >= 0 && enemy->currentNavNode < GAME_MAX_NAV_NODES) {
                if (enemy->targetNavNode < 0 || enemy->targetNavNode >= GAME_MAX_NAV_NODES ||
                    !state->navigationNodes[enemy->targetNavNode].active) {
                    enemy->targetNavNode = choose_patrol_target_node(state, enemy->currentNavNode, index, enemy->patrolPhase);
                }

                if (enemy->targetNavNode >= 0 && enemy->targetNavNode < GAME_MAX_NAV_NODES) {
                    Vec2 patrolTarget = state->navigationNodes[enemy->targetNavNode].position;
                    Vec2 toPatrolTarget = vec2_sub(patrolTarget, enemy->position);
                    float distanceToPatrolTarget = vec2_length(toPatrolTarget);

                    if (distanceToPatrolTarget < 34.0f) {
                        enemy->position = patrolTarget;
                        enemy->currentNavNode = enemy->targetNavNode;
                        enemy->targetNavNode = choose_patrol_target_node(state, enemy->currentNavNode, index, enemy->patrolPhase);
                        enemy->velocity = vec2_make(0.0f, 0.0f);
                    } else {
                        float terrainMultiplier = terrain_speed_multiplier(state, enemy->position);
                        enemy->velocity = vec2_scale(vec2_normalize(toPatrolTarget), 54.0f * terrainMultiplier);
                        attempt_move_enemy(state, enemy, vec2_add(enemy->position, vec2_scale(enemy->velocity, dt)));
                    }
                } else {
                    enemy->velocity = vec2_make(0.0f, 0.0f);
                }
            } else {
                float patrolAngle = state->missionTime * 0.28f + enemy->patrolPhase;
                float terrainMultiplier = terrain_speed_multiplier(state, enemy->position);
                enemy->velocity = vec2_make(cosf(patrolAngle), sinf(patrolAngle * 1.18f));
                attempt_move_enemy(state, enemy, vec2_add(enemy->position, vec2_scale(enemy->velocity, 34.0f * terrainMultiplier * dt)));
            }
        }
    }
}

static void register_default_loadout_for_mission(MissionType missionType) {
    game_content_add_mission_loadout_entry(missionType, "mk18_carbine", LoadoutSlotHint_Primary);
    game_content_add_mission_loadout_entry(missionType, "m17_sidearm", LoadoutSlotHint_Secondary);
    game_content_add_mission_loadout_entry(missionType, "field_knife", LoadoutSlotHint_Melee);
}

static void register_default_content(void) {
    clear_content_database_internal();

    game_content_add_item_template("mk18_carbine", "MK18 Carbine", ItemKind_Gun, AmmoType_556, WeaponClass_Carbine, 1, 30, 30, 32.0f, 780.0f, false, 0.055f, 960.0f, FireMode_Auto, fire_mode_mask(FireMode_Semi) | fire_mode_mask(FireMode_Auto), true, true, true);
    game_content_add_item_template("m17_sidearm", "M17 Sidearm", ItemKind_Gun, AmmoType_9mm, WeaponClass_Pistol, 1, 17, 17, 20.0f, 520.0f, false, 0.042f, 700.0f, FireMode_Semi, fire_mode_mask(FireMode_Semi), true, false, false);
    game_content_add_item_template("field_knife", "Field Knife", ItemKind_Blade, AmmoType_None, WeaponClass_Knife, 1, 0, 0, 52.0f, 70.0f, false, 0.0f, 0.0f, FireMode_Semi, fire_mode_mask(FireMode_Semi), false, false, false);
    game_content_add_item_template("ammo_556_ball", "5.56 Ball", ItemKind_BulletBox, AmmoType_556, WeaponClass_None, 30, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("stanag_mag", "STANAG Magazine", ItemKind_Magazine, AmmoType_556, WeaponClass_None, 1, 30, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("ammo_9mm_mag", "9mm Magazine", ItemKind_Magazine, AmmoType_9mm, WeaponClass_None, 2, 17, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("threaded_suppressor", "Threaded Suppressor", ItemKind_Attachment, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, true, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("combat_gauze", "Combat Gauze", ItemKind_Medkit, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("recon_rifle", "Recon Rifle", ItemKind_Gun, AmmoType_556, WeaponClass_Rifle, 1, 20, 20, 42.0f, 900.0f, true, 0.034f, 1100.0f, FireMode_Semi, fire_mode_mask(FireMode_Semi), true, true, true);
    game_content_add_item_template("vx9_carbine", "VX-9 Carbine", ItemKind_Gun, AmmoType_556, WeaponClass_Carbine, 1, 24, 24, 30.0f, 760.0f, false, 0.060f, 900.0f, FireMode_Burst, fire_mode_mask(FireMode_Semi) | fire_mode_mask(FireMode_Burst) | fire_mode_mask(FireMode_Auto), true, true, false);
    game_content_add_item_template("suppressed_scout_rifle", "Suppressed Scout Rifle", ItemKind_Gun, AmmoType_556, WeaponClass_Rifle, 1, 20, 20, 44.0f, 920.0f, true, 0.030f, 1120.0f, FireMode_Semi, fire_mode_mask(FireMode_Semi), true, true, true);
    game_content_add_item_template("breaching_knife", "Breaching Knife", ItemKind_Blade, AmmoType_None, WeaponClass_Knife, 1, 0, 0, 68.0f, 80.0f, false, 0.0f, 0.0f, FireMode_Semi, fire_mode_mask(FireMode_Semi), false, false, false);

    game_content_add_item_template("cache_ledger", "Cache Ledger", ItemKind_Objective, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("firing_codes", "Firing Codes", ItemKind_Objective, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("hostage_beacon", "Hostage Beacon", ItemKind_Objective, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("observation_reel", "Observation Reel", ItemKind_Objective, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("radio_snapshot", "Radio Snapshot", ItemKind_Objective, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("convoy_manifest", "Convoy Manifest", ItemKind_Objective, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);
    game_content_add_item_template("crypto_tablet", "Crypto Tablet", ItemKind_Objective, AmmoType_None, WeaponClass_None, 1, 0, 0, 0.0f, 0.0f, false, 0.0f, 0.0f, FireMode_Semi, 0, false, false, false);

    register_default_loadout_for_mission(MissionType_CacheRaid);
    register_default_loadout_for_mission(MissionType_HostageRecovery);
    register_default_loadout_for_mission(MissionType_ReconExfil);
    register_default_loadout_for_mission(MissionType_ConvoyAmbush);

    game_content_add_mission_loot_entry(MissionType_CacheRaid, "cache_ledger", 530.0f, 180.0f);
    game_content_add_mission_loot_entry(MissionType_CacheRaid, "firing_codes", 860.0f, 460.0f);
    game_content_add_mission_loot_entry(MissionType_CacheRaid, "ammo_556_ball", -860.0f, -440.0f);
    game_content_add_mission_loot_entry(MissionType_CacheRaid, "stanag_mag", -440.0f, -250.0f);
    game_content_add_mission_loot_entry(MissionType_CacheRaid, "threaded_suppressor", 210.0f, 20.0f);
    game_content_add_mission_loot_entry(MissionType_CacheRaid, "recon_rifle", 760.0f, 380.0f);
    game_content_add_mission_loot_entry(MissionType_CacheRaid, "combat_gauze", 960.0f, 420.0f);

    game_content_add_mission_loot_entry(MissionType_HostageRecovery, "hostage_beacon", 420.0f, 260.0f);
    game_content_add_mission_loot_entry(MissionType_HostageRecovery, "ammo_9mm_mag", -420.0f, 180.0f);
    game_content_add_mission_loot_entry(MissionType_HostageRecovery, "ammo_556_ball", 80.0f, 120.0f);
    game_content_add_mission_loot_entry(MissionType_HostageRecovery, "threaded_suppressor", 720.0f, 20.0f);
    game_content_add_mission_loot_entry(MissionType_HostageRecovery, "vx9_carbine", 860.0f, -220.0f);
    game_content_add_mission_loot_entry(MissionType_HostageRecovery, "combat_gauze", 520.0f, 320.0f);

    game_content_add_mission_loot_entry(MissionType_ReconExfil, "observation_reel", 260.0f, -120.0f);
    game_content_add_mission_loot_entry(MissionType_ReconExfil, "radio_snapshot", -40.0f, 420.0f);
    game_content_add_mission_loot_entry(MissionType_ReconExfil, "ammo_556_ball", 720.0f, -520.0f);
    game_content_add_mission_loot_entry(MissionType_ReconExfil, "ammo_9mm_mag", 220.0f, -40.0f);
    game_content_add_mission_loot_entry(MissionType_ReconExfil, "suppressed_scout_rifle", -180.0f, 280.0f);
    game_content_add_mission_loot_entry(MissionType_ReconExfil, "combat_gauze", -760.0f, 540.0f);
    game_content_add_mission_loot_entry(MissionType_ReconExfil, "threaded_suppressor", 420.0f, 220.0f);

    game_content_add_mission_loot_entry(MissionType_ConvoyAmbush, "convoy_manifest", 300.0f, 60.0f);
    game_content_add_mission_loot_entry(MissionType_ConvoyAmbush, "crypto_tablet", -20.0f, 60.0f);
    game_content_add_mission_loot_entry(MissionType_ConvoyAmbush, "ammo_556_ball", 920.0f, -120.0f);
    game_content_add_mission_loot_entry(MissionType_ConvoyAmbush, "stanag_mag", 620.0f, -120.0f);
    game_content_add_mission_loot_entry(MissionType_ConvoyAmbush, "ammo_9mm_mag", -300.0f, 220.0f);
    game_content_add_mission_loot_entry(MissionType_ConvoyAmbush, "breaching_knife", -720.0f, 220.0f);
    game_content_add_mission_loot_entry(MissionType_ConvoyAmbush, "combat_gauze", -860.0f, -220.0f);
}

static void ensure_content_database_loaded(void) {
    if (sContentItemTemplateCount == 0) {
        register_default_content();
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
    player->inventoryCount = 0;
    player->selectedIndex = -1;
    player->primaryIndex = -1;
    player->secondaryIndex = -1;
    player->meleeIndex = -1;
    player->ammo556 = 120;
    player->ammo9mm = 51;
    player->ammoShell = 0;
    player->burstShotsRemaining = 0;
    player->triggerHeldLastFrame = false;
    memset(player->inventory, 0, sizeof(player->inventory));
}

static void setup_cache_raid(GameState *state) {
    int northGateInteractable;
    int infilNode;
    int roadNode;
    int treelineNode;
    int gateNode;
    int compoundNode;
    int towerNode;
    int extractNode;

    copy_name(state->missionName, sizeof(state->missionName), "Cache Raid");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Ridge approach. Breach the northern gate, strip the cache compound, tap the relay if time allows, and extract east.");
    state->objectiveTarget = 2;
    state->extractionZone = vec2_make(1050.0f, 640.0f);
    state->extractionRadius = 100.0f;
    setup_common_player(state, vec2_make(-1120.0f, -620.0f));

    paint_terrain_rect(state, vec2_make(-980.0f, -620.0f), vec2_make(360.0f, 280.0f), TerrainMaterial_Forest, 4.0f, true);
    paint_terrain_rect(state, vec2_make(520.0f, 220.0f), vec2_make(420.0f, 320.0f), TerrainMaterial_Compound, 8.0f, false);

    add_structure(state, StructureKind_Road, vec2_make(-180.0f, -250.0f), vec2_make(1240.0f, 76.0f), 0.06f, false, false, false, false);
    add_structure(state, StructureKind_Ridge, vec2_make(-380.0f, -40.0f), vec2_make(340.0f, 160.0f), -0.12f, true, true, false, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-720.0f, -300.0f), vec2_make(210.0f, 190.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(30.0f, 120.0f), vec2_make(180.0f, 160.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Building, vec2_make(520.0f, 180.0f), vec2_make(260.0f, 180.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(430.0f, 320.0f), vec2_make(120.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(610.0f, 320.0f), vec2_make(120.0f, 24.0f), 0.0f, true, true, true, false);
    northGateInteractable = add_gate(state, vec2_make(520.0f, 320.0f), false, "North gate");
    add_structure(state, StructureKind_LowWall, vec2_make(360.0f, 180.0f), vec2_make(24.0f, 220.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(680.0f, 180.0f), vec2_make(24.0f, 220.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_Tower, vec2_make(860.0f, 460.0f), vec2_make(80.0f, 80.0f), 0.0f, true, true, false, false);

    infilNode = add_navigation_node(state, vec2_make(-1060.0f, -560.0f), 0.94f, true, false, false, false);
    roadNode = add_navigation_node(state, vec2_make(-460.0f, -260.0f), 0.88f, false, false, false, false);
    treelineNode = add_navigation_node(state, vec2_make(40.0f, 120.0f), 0.92f, true, false, false, false);
    gateNode = add_navigation_node(state, vec2_make(500.0f, 300.0f), 0.96f, true, false, false, false);
    compoundNode = add_navigation_node(state, vec2_make(520.0f, 180.0f), 0.98f, true, false, true, false);
    towerNode = add_navigation_node(state, vec2_make(860.0f, 460.0f), 1.06f, true, true, true, false);
    extractNode = add_navigation_node(state, vec2_make(1040.0f, 640.0f), 0.9f, false, false, false, true);

    add_navigation_link(state, infilNode, roadNode, -1);
    add_navigation_link(state, roadNode, treelineNode, -1);
    add_navigation_link(state, treelineNode, gateNode, -1);
    add_navigation_link(state, gateNode, compoundNode, northGateInteractable);
    add_navigation_link(state, compoundNode, towerNode, -1);
    add_navigation_link(state, towerNode, extractNode, -1);

    add_interactable(state, InteractableKind_SupplyCrate, vec2_make(-900.0f, -430.0f), vec2_make(58.0f, 40.0f), 0.0f, -1, false, true, 0.0f, 60, 17, 10, "Landing zone crate");
    add_interactable(state, InteractableKind_DeadDrop, vec2_make(40.0f, 140.0f), vec2_make(42.0f, 42.0f), 0.0f, -1, false, true, 0.0f, 30, 0, 0, "hide-site satchel");
    add_interactable(state, InteractableKind_Radio, vec2_make(860.0f, 520.0f), vec2_make(34.0f, 34.0f), 0.0f, -1, false, true, 0.0f, 0, 0, 0, "relay radio");
    add_interactable(state, InteractableKind_EmplacedWeapon, vec2_make(790.0f, 430.0f), vec2_make(42.0f, 28.0f), 0.0f, -1, false, false, 0.0f, 0, 0, 0, "watchtower MG");

    add_enemy(state, vec2_make(-180.0f, -120.0f), 0.2f);
    add_enemy(state, vec2_make(260.0f, 140.0f), 0.9f);
    add_enemy(state, vec2_make(560.0f, 60.0f), 1.8f);
    add_enemy(state, vec2_make(780.0f, 300.0f), 2.6f);
    add_enemy(state, vec2_make(960.0f, 540.0f), 3.3f);
}

static void setup_hostage_recovery(GameState *state) {
    int safehouseGateInteractable;
    int westNode;
    int crossroadNode;
    int villageNode;
    int gateNode;
    int safehouseNode;
    int southRoadNode;
    int extractNode;

    copy_name(state->missionName, sizeof(state->missionName), "Hostage Recovery");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Push the village blocks, cut through the safehouse gate, lift the beacon, and use the radio net to keep the exfil route clean.");
    state->objectiveTarget = 1;
    state->extractionZone = vec2_make(160.0f, -760.0f);
    state->extractionRadius = 96.0f;
    setup_common_player(state, vec2_make(-980.0f, 540.0f));

    paint_terrain_rect(state, vec2_make(420.0f, 250.0f), vec2_make(620.0f, 380.0f), TerrainMaterial_Compound, 10.0f, false);
    paint_terrain_rect(state, vec2_make(820.0f, -280.0f), vec2_make(340.0f, 220.0f), TerrainMaterial_Rock, 12.0f, false);

    add_structure(state, StructureKind_Road, vec2_make(-120.0f, 120.0f), vec2_make(1260.0f, 94.0f), 0.0f, false, false, false, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-720.0f, 300.0f), vec2_make(220.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Building, vec2_make(-180.0f, 260.0f), vec2_make(180.0f, 120.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Building, vec2_make(120.0f, 260.0f), vec2_make(180.0f, 120.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Building, vec2_make(420.0f, 260.0f), vec2_make(220.0f, 150.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(330.0f, 420.0f), vec2_make(140.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(510.0f, 420.0f), vec2_make(140.0f, 24.0f), 0.0f, true, true, true, false);
    safehouseGateInteractable = add_gate(state, vec2_make(420.0f, 420.0f), false, "Safehouse gate");
    add_structure(state, StructureKind_LowWall, vec2_make(560.0f, 250.0f), vec2_make(24.0f, 220.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(760.0f, -40.0f), vec2_make(210.0f, 200.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Ridge, vec2_make(860.0f, -300.0f), vec2_make(280.0f, 140.0f), 0.0f, true, true, false, false);

    westNode = add_navigation_node(state, vec2_make(-820.0f, 420.0f), 0.92f, true, false, false, false);
    crossroadNode = add_navigation_node(state, vec2_make(-120.0f, 120.0f), 0.88f, false, false, false, false);
    villageNode = add_navigation_node(state, vec2_make(160.0f, 260.0f), 0.96f, true, false, false, false);
    gateNode = add_navigation_node(state, vec2_make(420.0f, 420.0f), 0.98f, true, false, false, false);
    safehouseNode = add_navigation_node(state, vec2_make(420.0f, 260.0f), 1.0f, true, false, true, false);
    southRoadNode = add_navigation_node(state, vec2_make(220.0f, -180.0f), 0.9f, false, false, false, false);
    extractNode = add_navigation_node(state, vec2_make(160.0f, -720.0f), 0.9f, false, false, false, true);

    add_navigation_link(state, westNode, crossroadNode, -1);
    add_navigation_link(state, crossroadNode, villageNode, -1);
    add_navigation_link(state, villageNode, gateNode, -1);
    add_navigation_link(state, gateNode, safehouseNode, safehouseGateInteractable);
    add_navigation_link(state, safehouseNode, southRoadNode, -1);
    add_navigation_link(state, southRoadNode, extractNode, -1);

    add_interactable(state, InteractableKind_SupplyCrate, vec2_make(500.0f, 340.0f), vec2_make(58.0f, 40.0f), 0.0f, -1, false, true, 0.0f, 45, 34, 15, "aid-and-ammo crate");
    add_interactable(state, InteractableKind_DeadDrop, vec2_make(-660.0f, 340.0f), vec2_make(42.0f, 42.0f), 0.0f, -1, false, true, 0.0f, 0, 17, 0, "village dead drop");
    add_interactable(state, InteractableKind_Radio, vec2_make(760.0f, -40.0f), vec2_make(34.0f, 34.0f), 0.0f, -1, false, true, 0.0f, 0, 0, 0, "street relay");
    add_interactable(state, InteractableKind_EmplacedWeapon, vec2_make(610.0f, 430.0f), vec2_make(42.0f, 28.0f), 0.0f, -1, false, false, 0.0f, 0, 0, 0, "courtyard MG");

    add_enemy(state, vec2_make(-360.0f, 180.0f), 0.4f);
    add_enemy(state, vec2_make(-80.0f, 260.0f), 1.2f);
    add_enemy(state, vec2_make(220.0f, 240.0f), 2.1f);
    add_enemy(state, vec2_make(520.0f, 220.0f), 3.0f);
    add_enemy(state, vec2_make(740.0f, -60.0f), 3.7f);
    add_enemy(state, vec2_make(960.0f, -280.0f), 4.3f);
}

static void setup_recon_exfil(GameState *state) {
    int observationGateInteractable;
    int infilNode;
    int woodsNode;
    int ridgeNode;
    int centralGateNode;
    int shackNode;
    int northTreeNode;
    int extractNode;

    copy_name(state->missionName, sizeof(state->missionName), "Recon & Exfil");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Move the tree line, pull the ridge observation package, probe the shack net, and ghost north once the map is filled in.");
    state->objectiveTarget = 2;
    state->extractionZone = vec2_make(-1040.0f, 700.0f);
    state->extractionRadius = 96.0f;
    setup_common_player(state, vec2_make(1060.0f, -640.0f));

    paint_terrain_rect(state, vec2_make(540.0f, -360.0f), vec2_make(540.0f, 260.0f), TerrainMaterial_Forest, 8.0f, true);
    paint_terrain_rect(state, vec2_make(-620.0f, 500.0f), vec2_make(360.0f, 260.0f), TerrainMaterial_Forest, 10.0f, true);

    add_structure(state, StructureKind_Ridge, vec2_make(260.0f, -120.0f), vec2_make(420.0f, 150.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Ridge, vec2_make(-220.0f, 220.0f), vec2_make(460.0f, 170.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(780.0f, -360.0f), vec2_make(260.0f, 210.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(420.0f, 220.0f), vec2_make(240.0f, 200.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-620.0f, 500.0f), vec2_make(240.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Building, vec2_make(-40.0f, 420.0f), vec2_make(180.0f, 120.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(70.0f, 10.0f), vec2_make(120.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(170.0f, 10.0f), vec2_make(60.0f, 24.0f), 0.0f, true, true, true, false);
    observationGateInteractable = add_gate(state, vec2_make(120.0f, 10.0f), false, "Observation gate");
    add_structure(state, StructureKind_Road, vec2_make(-520.0f, 20.0f), vec2_make(720.0f, 76.0f), -0.15f, false, false, false, false);

    infilNode = add_navigation_node(state, vec2_make(980.0f, -620.0f), 0.94f, true, false, false, false);
    woodsNode = add_navigation_node(state, vec2_make(780.0f, -360.0f), 0.9f, true, false, false, false);
    ridgeNode = add_navigation_node(state, vec2_make(260.0f, -120.0f), 1.04f, true, true, true, false);
    centralGateNode = add_navigation_node(state, vec2_make(120.0f, 10.0f), 0.96f, true, false, false, false);
    shackNode = add_navigation_node(state, vec2_make(-40.0f, 420.0f), 0.98f, true, false, true, false);
    northTreeNode = add_navigation_node(state, vec2_make(-620.0f, 500.0f), 0.9f, true, false, false, false);
    extractNode = add_navigation_node(state, vec2_make(-1040.0f, 700.0f), 0.9f, false, false, false, true);

    add_navigation_link(state, infilNode, woodsNode, -1);
    add_navigation_link(state, woodsNode, ridgeNode, -1);
    add_navigation_link(state, ridgeNode, centralGateNode, -1);
    add_navigation_link(state, centralGateNode, shackNode, observationGateInteractable);
    add_navigation_link(state, shackNode, northTreeNode, -1);
    add_navigation_link(state, northTreeNode, extractNode, -1);

    add_interactable(state, InteractableKind_SupplyCrate, vec2_make(-740.0f, 560.0f), vec2_make(58.0f, 40.0f), 0.0f, -1, false, true, 0.0f, 60, 17, 0, "concealed resupply crate");
    add_interactable(state, InteractableKind_DeadDrop, vec2_make(430.0f, 240.0f), vec2_make(42.0f, 42.0f), 0.0f, -1, false, true, 0.0f, 30, 17, 0, "treeline dead drop");
    add_interactable(state, InteractableKind_Radio, vec2_make(-20.0f, 460.0f), vec2_make(34.0f, 34.0f), 0.0f, -1, false, true, 0.0f, 0, 0, 0, "shack receiver");
    add_interactable(state, InteractableKind_EmplacedWeapon, vec2_make(240.0f, -30.0f), vec2_make(42.0f, 28.0f), 0.0f, -1, false, false, 0.0f, 0, 0, 0, "ridge LMG");

    add_enemy(state, vec2_make(420.0f, -220.0f), 0.8f);
    add_enemy(state, vec2_make(180.0f, 60.0f), 1.6f);
    add_enemy(state, vec2_make(-80.0f, 380.0f), 2.4f);
    add_enemy(state, vec2_make(-420.0f, 200.0f), 3.1f);
    add_enemy(state, vec2_make(-740.0f, 540.0f), 4.0f);
}

static void setup_convoy_ambush(GameState *state) {
    int roadblockGateInteractable;
    int eastNode;
    int convoyNode;
    int centerNode;
    int roadblockNode;
    int fallbackNode;
    int ridgeNode;
    int extractNode;

    copy_name(state->missionName, sizeof(state->missionName), "Convoy Ambush");
    copy_name(state->missionBrief, sizeof(state->missionBrief), "Break the road column, strip the manifest and tablet, raid the dead drop and support point if needed, then slide west through the trees.");
    state->objectiveTarget = 2;
    state->extractionZone = vec2_make(-1100.0f, 140.0f);
    state->extractionRadius = 100.0f;
    setup_common_player(state, vec2_make(1040.0f, 60.0f));

    paint_terrain_rect(state, vec2_make(60.0f, 60.0f), vec2_make(1560.0f, 120.0f), TerrainMaterial_Road, -5.0f, false);
    paint_terrain_rect(state, vec2_make(-760.0f, 120.0f), vec2_make(420.0f, 280.0f), TerrainMaterial_Forest, 6.0f, true);

    add_structure(state, StructureKind_Road, vec2_make(60.0f, 60.0f), vec2_make(1520.0f, 88.0f), 0.0f, false, false, false, false);
    add_structure(state, StructureKind_Convoy, vec2_make(300.0f, 60.0f), vec2_make(220.0f, 80.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_Convoy, vec2_make(-20.0f, 60.0f), vec2_make(220.0f, 80.0f), 0.0f, true, true, false, false);
    add_structure(state, StructureKind_LowWall, vec2_make(-320.0f, 220.0f), vec2_make(160.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_LowWall, vec2_make(-180.0f, 220.0f), vec2_make(80.0f, 24.0f), 0.0f, true, true, true, false);
    roadblockGateInteractable = add_gate(state, vec2_make(-260.0f, 220.0f), false, "Roadblock gate");
    add_structure(state, StructureKind_LowWall, vec2_make(620.0f, -120.0f), vec2_make(260.0f, 24.0f), 0.0f, true, true, true, false);
    add_structure(state, StructureKind_TreeCluster, vec2_make(860.0f, -220.0f), vec2_make(260.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_TreeCluster, vec2_make(-620.0f, 180.0f), vec2_make(260.0f, 220.0f), 0.0f, false, false, false, true);
    add_structure(state, StructureKind_Ridge, vec2_make(-840.0f, -220.0f), vec2_make(320.0f, 180.0f), 0.0f, true, true, false, false);

    eastNode = add_navigation_node(state, vec2_make(1040.0f, 60.0f), 0.88f, false, false, false, false);
    convoyNode = add_navigation_node(state, vec2_make(520.0f, 60.0f), 0.92f, true, false, false, false);
    centerNode = add_navigation_node(state, vec2_make(120.0f, 60.0f), 0.96f, true, false, true, false);
    roadblockNode = add_navigation_node(state, vec2_make(-260.0f, 220.0f), 0.98f, true, false, false, false);
    fallbackNode = add_navigation_node(state, vec2_make(-620.0f, 180.0f), 0.92f, true, false, false, false);
    ridgeNode = add_navigation_node(state, vec2_make(-840.0f, -220.0f), 1.02f, true, true, false, false);
    extractNode = add_navigation_node(state, vec2_make(-1100.0f, 140.0f), 0.9f, false, false, false, true);

    add_navigation_link(state, eastNode, convoyNode, -1);
    add_navigation_link(state, convoyNode, centerNode, -1);
    add_navigation_link(state, centerNode, roadblockNode, roadblockGateInteractable);
    add_navigation_link(state, roadblockNode, fallbackNode, -1);
    add_navigation_link(state, fallbackNode, extractNode, -1);
    add_navigation_link(state, centerNode, ridgeNode, -1);
    add_navigation_link(state, ridgeNode, extractNode, -1);

    add_interactable(state, InteractableKind_SupplyCrate, vec2_make(660.0f, -120.0f), vec2_make(58.0f, 40.0f), 0.0f, -1, false, true, 0.0f, 60, 17, 10, "convoy crate");
    add_interactable(state, InteractableKind_DeadDrop, vec2_make(-660.0f, 220.0f), vec2_make(42.0f, 42.0f), 0.0f, -1, false, true, 0.0f, 30, 17, 0, "fallback dead drop");
    add_interactable(state, InteractableKind_Radio, vec2_make(240.0f, 120.0f), vec2_make(34.0f, 34.0f), 0.0f, -1, false, true, 0.0f, 0, 0, 0, "convoy radio");
    add_interactable(state, InteractableKind_EmplacedWeapon, vec2_make(-340.0f, 240.0f), vec2_make(42.0f, 28.0f), 0.0f, -1, false, false, 0.0f, 0, 0, 0, "roadblock gun");

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
    state->radioIntelUnlocked = false;
    state->radioReportCooldown = 0.0f;
    initialize_terrain(state, mission);

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

    apply_mission_content(state, mission);
    update_command_route(state);
    update_discovery(state);
    update_radio_report(state, 0.0f);
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
        interact_nearby(state);
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
    update_interactables(state, dt);
    update_enemies(state, dt);
    update_discovery(state);
    update_command_route(state);
    update_radio_report(state, dt);

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

size_t game_interactable_count(const GameState *state) {
    size_t count = 0;
    size_t index;
    for (index = 0; index < GAME_MAX_INTERACTABLES; index += 1) {
        if (state->interactables[index].active) {
            count += 1;
        }
    }
    return count;
}

const Interactable *game_interactable_at(const GameState *state, size_t index) {
    size_t count = 0;
    size_t interactableIndex;
    for (interactableIndex = 0; interactableIndex < GAME_MAX_INTERACTABLES; interactableIndex += 1) {
        if (!state->interactables[interactableIndex].active) {
            continue;
        }
        if (count == index) {
            return &state->interactables[interactableIndex];
        }
        count += 1;
    }
    return NULL;
}

size_t game_terrain_tile_count(const GameState *state) {
    size_t count = 0;
    size_t index;
    for (index = 0; index < GAME_MAX_TERRAIN_TILES; index += 1) {
        if (state->terrainTiles[index].active) {
            count += 1;
        }
    }
    return count;
}

const TerrainTile *game_terrain_tile_at(const GameState *state, size_t index) {
    if (index >= GAME_MAX_TERRAIN_TILES || !state->terrainTiles[index].active) {
        return NULL;
    }
    return &state->terrainTiles[index];
}

size_t game_navigation_node_count(const GameState *state) {
    size_t count = 0;
    size_t index;
    for (index = 0; index < GAME_MAX_NAV_NODES; index += 1) {
        if (state->navigationNodes[index].active) {
            count += 1;
        }
    }
    return count;
}

const NavigationNode *game_navigation_node_at(const GameState *state, size_t index) {
    size_t count = 0;
    size_t nodeIndex;
    for (nodeIndex = 0; nodeIndex < GAME_MAX_NAV_NODES; nodeIndex += 1) {
        if (!state->navigationNodes[nodeIndex].active) {
            continue;
        }
        if (count == index) {
            return &state->navigationNodes[nodeIndex];
        }
        count += 1;
    }
    return NULL;
}

size_t game_command_route_count(const GameState *state) {
    return (size_t) state->commandRouteCount;
}

const Vec2 *game_command_route_point_at(const GameState *state, size_t index) {
    if (index >= (size_t) state->commandRouteCount) {
        return NULL;
    }
    return &state->commandRoutePoints[index];
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

bool game_radio_intel_unlocked(const GameState *state) {
    return state->radioIntelUnlocked;
}

const char *game_radio_report(const GameState *state) {
    return state->radioReport;
}
