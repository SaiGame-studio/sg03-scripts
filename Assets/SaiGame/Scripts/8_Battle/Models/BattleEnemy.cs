using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class BattleEnemy
    {
        public bool alive;
        public int attack;
        public int defense;
        public int hp;
        public string id;
        public int max_hp;
        public string name;
        public int position;
        public int speed;
    }
}
