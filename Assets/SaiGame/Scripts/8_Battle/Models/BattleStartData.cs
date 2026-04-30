using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class BattleStartData
    {
        public string[] battle_log;
        public bool battle_over;
        public BattleEnemy[] enemies;
        public BattlePlayerChar[] player_chars;
        public int turn;
        public bool victory;
    }
}
