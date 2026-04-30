using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class BattleSessionsResponse
    {
        public int limit;
        public int offset;
        public int total;
        public BattleSessionData[] sessions;
    }
}
