using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class EquipItemRequest
    {
        public string item_id;
        public string slot_key;
        public string slot_data;
    }
}
