using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class BattleSessionData
    {
        public string id;
        public string game_id;
        public string player_id;
        public string status;
        public string started_at;
        public string expires_at;
        public string ended_at;
        public BattleStartData start_data;
        public BattleEndData end_data;
    }
}
