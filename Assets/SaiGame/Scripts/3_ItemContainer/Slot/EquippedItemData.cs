using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class EquippedItemData
    {
        public string slot_key;
        public string slot_name;
        public string item_id;
        public string item_definition_id;
        public string item_name;
        public string category;
        public string rarity;
        // JsonUtility cannot deserialize arbitrary objects into a string field;
        // this is populated manually from the raw JSON after deserialization.
        [NonSerialized] public string slot_data_raw;
    }
}
