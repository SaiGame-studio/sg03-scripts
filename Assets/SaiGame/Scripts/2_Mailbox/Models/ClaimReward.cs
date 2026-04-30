using System;

namespace SaiGame.Services
{
    /// <summary>
    /// A single reward item returned after claiming a message.
    /// </summary>
    [Serializable]
    public class ClaimReward
    {
        public string type;
        public string definition_id;
        public int quantity;
    }
}
