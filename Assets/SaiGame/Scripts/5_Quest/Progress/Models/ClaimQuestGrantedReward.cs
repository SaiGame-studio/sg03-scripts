using System;

namespace SaiGame.Services
{
    /// <summary>
    /// A single reward granted when claiming a completed quest.
    /// </summary>
    [Serializable]
    public class ClaimQuestGrantedReward
    {
        public string reward_type;
        public int amount;
        public int quantity;
        public string item_definition_id;
    }
}
