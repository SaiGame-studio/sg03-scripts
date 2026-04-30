using System;
using UnityEngine;

namespace SaiGame.Services
{
    [Serializable]
    public class EquipmentSlotsResponse
    {
        public EquipmentSlotData[] slots;
        public int total;
    }
}
