#import "GameLogic.h"

#pragma mark - Function Game

// Simple structure check: MatchGame has Match@0x90 and CameraCtrlMgr@0xD8
static bool looksMatchGame(uint64_t obj) {
    if (!isVaildPtr(obj)) return false;
    uint64_t match = ReadAddr<uint64_t>(obj + 0x90);
    uint64_t camMgr = ReadAddr<uint64_t>(obj + 0xD8);
    if (!isVaildPtr(match) || !isVaildPtr(camMgr)) return false;
    uint64_t lp = ReadAddr<uint64_t>(match + 0xD8);
    return isVaildPtr(lp);
}

// Runtime scan: walk module data for a MatchGame-shaped object.
// Called once; result is cached. Logs the offset so it can be hardcoded later.
static uint64_t scanMatchGame(uint64_t base) {
    if (!base) return 0;
    static uint64_t cached = 0;
    if (cached && looksMatchGame(cached)) return cached;

    // Typical Il2Cpp data section spans tens of MB. Scan in chunks.
    const uint64_t start = 0x800000;
    const uint64_t end   = 0x3000000;
    for (uint64_t off = start; off < end; off += 8) {
        uint64_t cand = ReadAddr<uint64_t>(base + off);
        if (!isVaildPtr(cand)) continue;
        if (looksMatchGame(cand)) {
            cached = cand;
            NSLog(@"[Vortex] MatchGame found at base+0x%llx -> %llx", off, cand);
            return cand;
        }
    }
    NSLog(@"[Vortex] MatchGame scan finished, not found");
    return 0;
}

uint64_t getMatchGame(uint64_t Moudule_Base) {
    // Try TypeInfo path first (may be outdated)
    uint64_t ti = ReadAddr<uint64_t>(Moudule_Base + 0xBFD8978);
    if (isVaildPtr(ti)) {
        uint64_t sf = ReadAddr<uint64_t>(ti + 0xB8);
        if (isVaildPtr(sf)) {
            uint64_t mg = ReadAddr<uint64_t>(sf + 0x8); // CurrentMatchGame
            if (looksMatchGame(mg)) return mg;
            mg = ReadAddr<uint64_t>(sf + 0x0); // CurrentGame fallback
            if (looksMatchGame(mg)) return mg;
        }
    }
    // Fallback: structure scan
    return scanMatchGame(Moudule_Base);
}

uint64_t getMatch(uint64_t matchgame) {
    return ReadAddr<uint64_t>(matchgame + 0x90);
}

uint64_t getLocalPlayer(uint64_t match) {
    return ReadAddr<uint64_t>(match + 0xD8);
}

uint64_t CameraMain(uint64_t matchgame) {
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchgame + 0xD8);
    return ReadAddr<uint64_t>(CameraControllerManager + 0x18);
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + 0x10);
    
    static float matrix[16];
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + 0xD8 + i * 0x4);
    }
    
    return matrix;
}

uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + 0x10);
}

uint64_t getHead(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x698); // protected ITransformNode HeadNode;
    return getTransNode(BodyPart);
}

uint64_t getHip(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x6A0); // protected ITransformNode HipNode;
    return getTransNode(BodyPart);
}

uint64_t getLeftAnkle(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x6D0); // protected ITransformNode m_LeftAnkleNode;
    return getTransNode(BodyPart);
}

uint64_t getRightAnkle(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x6D8); // protected ITransformNode m_RightAnkleNode;
    return getTransNode(BodyPart);
}

uint64_t getRightToeNode(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x6E8); // protected ITransformNode m_RightToeNode;
    return getTransNode(BodyPart);
}


uint64_t getLeftShoulder(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x708); // protected ITransformNode m_LeftArmNode;
    return getTransNode(BodyPart);
}

uint64_t getLeftElbow(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x730); // protected ITransformNode m_LeftForeArmNode;
    return getTransNode(BodyPart);
}

uint64_t getLeftHand(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x720); // protected ITransformNode m_LeftHandNode;
    return getTransNode(BodyPart);
}

uint64_t getRightShoulder(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x710); // protected ITransformNode m_RightArmNode;
    return getTransNode(BodyPart);
}

uint64_t getRightElbow(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x728); // protected ITransformNode m_RightForeArmNode;
    return getTransNode(BodyPart);
}

uint64_t getRightHand(uint64_t player) {
    uint64_t BodyPart = ReadAddr<uint64_t>(player + 0x718); // protected ITransformNode m_RightHandNode;
    return getTransNode(BodyPart);
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player) {
    COW_GamePlay_PlayerID_o myPlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + 0x408);
    COW_GamePlay_PlayerID_o PlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(Player + 0x408);
    
    int myTeamID = myPlayerID.m_TeamID;
    int TeamID = PlayerID.m_TeamID;
    
    return myTeamID == TeamID;
}

int GetDataUInt16(uint64_t player, int varID) {
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + 0x68);
    if (isVaildPtr(IPRIDataPool)) {
        uint64_t v2 = ReadAddr<uint64_t>(IPRIDataPool + 0x10);
        uint64_t v4 = ReadAddr<uint64_t>(v2 + 0x8 * varID + 0x20);
        int v6 = ReadAddr<int>(v4 + 0x18);
        return v6;
    }
    return 0;
}

int get_CurHP(uint64_t Player) {
    return GetDataUInt16(Player, 0);
}

int get_MaxHP(uint64_t Player) {
    return GetDataUInt16(Player, 1);
}

