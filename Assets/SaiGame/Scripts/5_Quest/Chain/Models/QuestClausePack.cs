using System;

namespace SaiGame.Services
{
    /// <summary>
    /// A gacha pack requirement inside a quest condition clause.
    /// </summary>
    [Serializable]
    public class QuestClausePack
    {
        public string gacha_pack_id;
        public int quantity;
    }
}
