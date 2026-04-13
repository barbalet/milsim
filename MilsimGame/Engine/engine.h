#ifndef MILSIM_ENGINE_H
#define MILSIM_ENGINE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GAME_MAX_ITEMS 96
#define GAME_MAX_PROJECTILES 64
#define GAME_MAX_ENEMIES 16
#define GAME_MAX_TEAMMATES 3
#define GAME_MAX_INVENTORY 24
#define GAME_MAX_STRUCTURES 56
#define GAME_MAX_INTERACTABLES 24
#define GAME_TERRAIN_COLUMNS 14
#define GAME_TERRAIN_ROWS 10
#define GAME_MAX_TERRAIN_TILES (GAME_TERRAIN_COLUMNS * GAME_TERRAIN_ROWS)
#define GAME_MAX_NAV_NODES 48
#define GAME_MAX_NAV_LINKS 6
#define GAME_MAX_COMMAND_ROUTE_POINTS 24
#define GAME_EVENT_LENGTH 96

typedef enum AmmoType {
    AmmoType_None = 0,
    AmmoType_556 = 1,
    AmmoType_9mm = 2,
    AmmoType_Shell = 3
} AmmoType;

typedef enum WeaponClass {
    WeaponClass_None = 0,
    WeaponClass_Rifle = 1,
    WeaponClass_Carbine = 2,
    WeaponClass_Pistol = 3,
    WeaponClass_Knife = 4
} WeaponClass;

typedef enum ItemKind {
    ItemKind_None = 0,
    ItemKind_BulletBox = 1,
    ItemKind_Gun = 2,
    ItemKind_Magazine = 3,
    ItemKind_Blade = 4,
    ItemKind_Attachment = 5,
    ItemKind_Medkit = 6,
    ItemKind_Objective = 7
} ItemKind;

typedef enum FireMode {
    FireMode_Semi = 0,
    FireMode_Burst = 1,
    FireMode_Auto = 2
} FireMode;

typedef enum Stance {
    Stance_Stand = 0,
    Stance_Crouch = 1,
    Stance_Prone = 2
} Stance;

typedef enum WoundFlag {
    WoundFlag_None = 0,
    WoundFlag_Arm = 1 << 0,
    WoundFlag_Leg = 1 << 1,
    WoundFlag_Torso = 1 << 2,
    WoundFlag_Head = 1 << 3
} WoundFlag;

typedef enum FractureFlag {
    FractureFlag_None = 0,
    FractureFlag_Arm = 1 << 0,
    FractureFlag_Leg = 1 << 1
} FractureFlag;

typedef enum MissionType {
    MissionType_CacheRaid = 0,
    MissionType_HostageRecovery = 1,
    MissionType_ReconExfil = 2,
    MissionType_ConvoyAmbush = 3,
    MissionType_Count = 4
} MissionType;

typedef enum FireteamOrder {
    FireteamOrder_Follow = 0,
    FireteamOrder_Hold = 1,
    FireteamOrder_Assault = 2
} FireteamOrder;

typedef enum StructureKind {
    StructureKind_None = 0,
    StructureKind_Ridge = 1,
    StructureKind_Road = 2,
    StructureKind_TreeCluster = 3,
    StructureKind_Building = 4,
    StructureKind_LowWall = 5,
    StructureKind_Tower = 6,
    StructureKind_Convoy = 7,
    StructureKind_Door = 8
} StructureKind;

typedef enum TerrainMaterial {
    TerrainMaterial_Grass = 0,
    TerrainMaterial_Road = 1,
    TerrainMaterial_Mud = 2,
    TerrainMaterial_Rock = 3,
    TerrainMaterial_Compound = 4,
    TerrainMaterial_Forest = 5
} TerrainMaterial;

typedef enum InteractableKind {
    InteractableKind_None = 0,
    InteractableKind_Door = 1,
    InteractableKind_SupplyCrate = 2,
    InteractableKind_DeadDrop = 3,
    InteractableKind_Radio = 4,
    InteractableKind_EmplacedWeapon = 5
} InteractableKind;

typedef enum LoadoutSlotHint {
    LoadoutSlotHint_Auto = 0,
    LoadoutSlotHint_Primary = 1,
    LoadoutSlotHint_Secondary = 2,
    LoadoutSlotHint_Melee = 3,
    LoadoutSlotHint_Gear = 4
} LoadoutSlotHint;

typedef struct Vec2 {
    float x;
    float y;
} Vec2;

typedef struct InputState {
    float moveX;
    float moveY;
    float aimX;
    float aimY;
    float lean;
    bool wantsFire;
    bool wantsCollect;
    bool wantsReload;
    bool wantsSprint;
    bool wantsCycleNext;
    bool wantsCyclePrevious;
    bool wantsPrimary;
    bool wantsSecondary;
    bool wantsMelee;
    bool wantsTreatWounds;
    bool wantsToggleFireMode;
    bool wantsCrouchToggle;
    bool wantsProneToggle;
    bool wantsVault;
    bool wantsCycleFireteamOrder;
} InputState;

typedef struct InventoryItem {
    bool active;
    ItemKind kind;
    AmmoType ammoType;
    WeaponClass weaponClass;
    char name[32];
    int quantity;
    int magazineCapacity;
    int roundsInMagazine;
    bool roundChambered;
    float damage;
    float range;
    bool suppressed;
    float recoil;
    float muzzleVelocity;
    FireMode fireMode;
    unsigned int supportedFireModes;
    bool supportsSuppressor;
    bool supportsOptic;
    bool supportsLaser;
    bool supportsLight;
    bool supportsUnderbarrel;
    bool opticMounted;
    bool laserMounted;
    bool lightMounted;
    bool underbarrelMounted;
} InventoryItem;

typedef struct WorldItem {
    bool active;
    bool discovered;
    ItemKind kind;
    AmmoType ammoType;
    WeaponClass weaponClass;
    Vec2 position;
    char name[32];
    int quantity;
    int magazineCapacity;
    int roundsInMagazine;
    bool roundChambered;
    float damage;
    bool suppressed;
    float recoil;
    float muzzleVelocity;
    FireMode fireMode;
    unsigned int supportedFireModes;
    bool supportsSuppressor;
    bool supportsOptic;
    bool supportsLaser;
    bool supportsLight;
    bool supportsUnderbarrel;
    bool opticMounted;
    bool laserMounted;
    bool lightMounted;
    bool underbarrelMounted;
} WorldItem;

typedef struct Projectile {
    bool active;
    Vec2 position;
    Vec2 velocity;
    float ttl;
    float initialSpeed;
    float damage;
    bool fromPlayer;
    bool nearMissApplied;
    int penetrationsRemaining;
    float penetrationPower;
    bool softenedByVegetation;
} Projectile;

typedef struct Enemy {
    bool active;
    Vec2 position;
    Vec2 velocity;
    float health;
    float fireCooldown;
    float patrolPhase;
    float hitTimer;
    float suppression;
    float bleedingRate;
    float pain;
    unsigned int woundFlags;
    unsigned int fractureFlags;
    bool fallingBack;
    int currentNavNode;
    int targetNavNode;
} Enemy;

typedef struct Teammate {
    bool active;
    bool downed;
    Vec2 position;
    Vec2 velocity;
    Vec2 aim;
    float health;
    float fireCooldown;
    float hitTimer;
    float suppression;
    float bleedingRate;
    float pain;
    int currentRoutePoint;
    char callsign[24];
} Teammate;

typedef struct Structure {
    bool active;
    StructureKind kind;
    Vec2 position;
    Vec2 size;
    float rotation;
    bool blocksMovement;
    bool blocksProjectiles;
    bool vaultable;
    bool conceals;
} Structure;

typedef struct Interactable {
    bool active;
    bool discovered;
    InteractableKind kind;
    Vec2 position;
    Vec2 size;
    float rotation;
    int linkedStructureIndex;
    bool toggled;
    bool singleUse;
    float cooldown;
    int ammo556;
    int ammo9mm;
    int healthValue;
    char name[32];
} Interactable;

typedef struct TerrainTile {
    bool active;
    Vec2 position;
    Vec2 size;
    float height;
    TerrainMaterial material;
    float navigationCost;
    bool conceals;
} TerrainTile;

typedef struct NavigationNode {
    bool active;
    Vec2 position;
    float traversalCost;
    bool offersCover;
    bool elevated;
    bool objectiveAnchor;
    bool extractionAnchor;
    int linkCount;
    int links[GAME_MAX_NAV_LINKS];
    int doorInteractableIndices[GAME_MAX_NAV_LINKS];
} NavigationNode;

typedef struct Player {
    Vec2 position;
    Vec2 velocity;
    Vec2 aim;
    float health;
    float stamina;
    float fireCooldown;
    float lean;
    float hitTimer;
    float noiseTimer;
    float suppression;
    float bleedingRate;
    float pain;
    float staminaShock;
    unsigned int woundFlags;
    unsigned int fractureFlags;
    Stance stance;
    int inventoryCount;
    int selectedIndex;
    int primaryIndex;
    int secondaryIndex;
    int meleeIndex;
    int ammo556;
    int ammo9mm;
    int ammoShell;
    int burstShotsRemaining;
    bool triggerHeldLastFrame;
    InventoryItem inventory[GAME_MAX_INVENTORY];
} Player;

typedef struct GameState {
    Player player;
    WorldItem worldItems[GAME_MAX_ITEMS];
    Projectile projectiles[GAME_MAX_PROJECTILES];
    Enemy enemies[GAME_MAX_ENEMIES];
    Teammate teammates[GAME_MAX_TEAMMATES];
    Structure structures[GAME_MAX_STRUCTURES];
    Interactable interactables[GAME_MAX_INTERACTABLES];
    TerrainTile terrainTiles[GAME_MAX_TERRAIN_TILES];
    NavigationNode navigationNodes[GAME_MAX_NAV_NODES];
    Vec2 commandRoutePoints[GAME_MAX_COMMAND_ROUTE_POINTS];
    Vec2 fireteamHoldAnchor;
    MissionType missionType;
    Vec2 extractionZone;
    float extractionRadius;
    float missionTime;
    float radioReportCooldown;
    int objectiveCount;
    int objectiveTarget;
    int commandRouteCount;
    int collectedItemCount;
    int kills;
    FireteamOrder fireteamOrder;
    bool victory;
    bool missionFailed;
    bool radioIntelUnlocked;
    char missionName[32];
    char missionBrief[GAME_EVENT_LENGTH];
    char radioReport[GAME_EVENT_LENGTH];
    char lastEvent[GAME_EVENT_LENGTH];
} GameState;

void game_init(GameState *state);
void game_restart(GameState *state);
void game_next_mission(GameState *state);
void game_reset_input(InputState *input);
void game_update(GameState *state, const InputState *input, float dt);
void game_cycle_weapon(GameState *state, int direction);
void game_select_primary(GameState *state);
void game_select_secondary(GameState *state);
void game_select_melee(GameState *state);
void game_cycle_fireteam_order(GameState *state);
void game_set_fireteam_order(GameState *state, FireteamOrder order);

void game_content_reset(void);
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
                                    bool supportsLaser,
                                    bool supportsLight,
                                    bool supportsUnderbarrel,
                                    bool opticMounted,
                                    bool laserMounted,
                                    bool lightMounted,
                                    bool underbarrelMounted);
bool game_content_add_mission_loadout_entry(MissionType missionType, const char *templateIdentifier, LoadoutSlotHint slotHint);
bool game_content_add_mission_loot_entry(MissionType missionType, const char *templateIdentifier, float x, float y);
bool game_content_set_mission_script(MissionType missionType,
                                     const char *name,
                                     const char *brief,
                                     const char *initialEvent,
                                     const char *quietReport,
                                     const char *clearReport,
                                     const char *interceptCallsign);
void game_set_mission_cursor(MissionType missionType);
void game_refresh_loaded_state(GameState *state);

size_t game_collection_target(void);
float game_world_half_width(void);
float game_world_half_height(void);

const char *game_mission_name(const GameState *state);
const char *game_mission_brief(const GameState *state);
int game_mission_objective_count(const GameState *state);
int game_mission_objective_target(const GameState *state);
bool game_mission_ready_for_extract(const GameState *state);

const char *game_last_event(const GameState *state);
const char *game_selected_item_name(const GameState *state);
const char *game_selected_fire_mode_name(const GameState *state);
const char *game_player_stance_name(const GameState *state);

size_t game_inventory_count(const GameState *state);
const InventoryItem *game_inventory_item_at(const GameState *state, size_t index);
const char *game_inventory_item_name(const GameState *state, size_t index);
int game_selected_inventory_index(const GameState *state);

size_t game_world_item_count(const GameState *state);
const WorldItem *game_world_item_at(const GameState *state, size_t index);

size_t game_enemy_count(const GameState *state);
const Enemy *game_enemy_at(const GameState *state, size_t index);

size_t game_teammate_count(const GameState *state);
const Teammate *game_teammate_at(const GameState *state, size_t index);
FireteamOrder game_fireteam_order(const GameState *state);
const char *game_fireteam_order_name(const GameState *state);

size_t game_projectile_count(const GameState *state);
const Projectile *game_projectile_at(const GameState *state, size_t index);

size_t game_structure_count(const GameState *state);
const Structure *game_structure_at(const GameState *state, size_t index);

size_t game_interactable_count(const GameState *state);
const Interactable *game_interactable_at(const GameState *state, size_t index);

size_t game_terrain_tile_count(const GameState *state);
const TerrainTile *game_terrain_tile_at(const GameState *state, size_t index);

size_t game_navigation_node_count(const GameState *state);
const NavigationNode *game_navigation_node_at(const GameState *state, size_t index);
size_t game_command_route_count(const GameState *state);
const Vec2 *game_command_route_point_at(const GameState *state, size_t index);

float game_player_health(const GameState *state);
float game_player_stamina(const GameState *state);
float game_player_lean(const GameState *state);
int game_player_total_ammo(const GameState *state, AmmoType ammoType);
bool game_radio_intel_unlocked(const GameState *state);
const char *game_radio_report(const GameState *state);

#ifdef __cplusplus
}
#endif

#endif
