using System;

namespace SaiGame.Services
{
    /// <summary>
    /// An item required inside a quest condition clause.
    /// </summary>
    [Serializable]
    public class QuestClauseItem
    {
        public string item_definition_id;
        public int quantity;
    }
}
