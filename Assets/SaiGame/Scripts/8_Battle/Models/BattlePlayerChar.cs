using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class BattlePlayerChar
    {
        public bool alive;
        public int attack;
        public int defense;
        public int hp;
        public string id;
        public int max_hp;
        public int mp;
        public string name;
    }
}
