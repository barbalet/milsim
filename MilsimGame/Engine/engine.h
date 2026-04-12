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
#define GAME_MAX_INVENTORY 24
#define GAME_MAX_STRUCTURES 48
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

typedef enum MissionType {
    MissionType_CacheRaid = 0,
    MissionType_HostageRecovery = 1,
    MissionType_ReconExfil = 2,
    MissionType_ConvoyAmbush = 3,
    MissionType_Count = 4
} MissionType;

typedef enum StructureKind {
    StructureKind_None = 0,
    StructureKind_Ridge = 1,
    StructureKind_Road = 2,
    StructureKind_TreeCluster = 3,
    StructureKind_Building = 4,
    StructureKind_LowWall = 5,
    StructureKind_Tower = 6,
    StructureKind_Convoy = 7
} StructureKind;

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
    bool wantsToggleFireMode;
    bool wantsCrouchToggle;
    bool wantsProneToggle;
    bool wantsVault;
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
} InventoryItem;

typedef struct WorldItem {
    bool active;
    ItemKind kind;
    AmmoType ammoType;
    WeaponClass weaponClass;
    Vec2 position;
    char name[32];
    int quantity;
    int magazineCapacity;
    int roundsInMagazine;
    float damage;
    bool suppressed;
    float recoil;
    float muzzleVelocity;
    FireMode fireMode;
    unsigned int supportedFireModes;
    bool supportsSuppressor;
    bool supportsOptic;
    bool opticMounted;
} WorldItem;

typedef struct Projectile {
    bool active;
    Vec2 position;
    Vec2 velocity;
    float ttl;
    float damage;
    bool fromPlayer;
} Projectile;

typedef struct Enemy {
    bool active;
    Vec2 position;
    Vec2 velocity;
    float health;
    float fireCooldown;
    float patrolPhase;
    float hitTimer;
} Enemy;

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
    Structure structures[GAME_MAX_STRUCTURES];
    MissionType missionType;
    Vec2 extractionZone;
    float extractionRadius;
    float missionTime;
    int objectiveCount;
    int objectiveTarget;
    int collectedItemCount;
    int kills;
    bool victory;
    bool missionFailed;
    char missionName[32];
    char missionBrief[GAME_EVENT_LENGTH];
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

size_t game_projectile_count(const GameState *state);
const Projectile *game_projectile_at(const GameState *state, size_t index);

size_t game_structure_count(const GameState *state);
const Structure *game_structure_at(const GameState *state, size_t index);

float game_player_health(const GameState *state);
float game_player_stamina(const GameState *state);
float game_player_lean(const GameState *state);
int game_player_total_ammo(const GameState *state, AmmoType ammoType);

#ifdef __cplusplus
}
#endif

#endif
