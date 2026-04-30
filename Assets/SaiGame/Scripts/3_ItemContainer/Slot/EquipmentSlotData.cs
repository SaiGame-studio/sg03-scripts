using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class EquipmentSlotData
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string slot_key;
        public string name;
        public string description;
        public string[] allowed_categories;
        public string[] allowed_item_definition_ids;
        public EquipmentSlotMetadata metadata;
        public bool is_active;
        public string created_by;
        public string created_at;
        public string updated_at;
    }
}
