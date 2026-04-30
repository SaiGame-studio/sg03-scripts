using System;

namespace SaiGame.Services
{
    /// <summary>
    /// A single reward entry on a quest definition.
    /// </summary>
    [Serializable]
    public class QuestReward
    {
        public string reward_type;
        public int amount;
        public string item_definition_id;
        public int quantity_min;
        public int quantity_max;
    }
}
