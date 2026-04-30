using System;

namespace SaiGame.Services
{
    [Serializable]
    public class PresetDetailResponse
    {
        public PresetData container;
        public PresetSlotData[] slots;
    }
}
