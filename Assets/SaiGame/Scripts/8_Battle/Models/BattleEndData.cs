using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class BattleEndData
    {
        public int kills;
        public string summary;
        public int survival_pct;
        public int turns_taken;
        public bool victory;
    }
}
