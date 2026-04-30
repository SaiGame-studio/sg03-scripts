using System;

namespace SaiGame.Services
{
    /// <summary>
    /// A single condition clause within a quest definition.
    /// </summary>
    [Serializable]
    public class QuestClause
    {
        public string clause_id;
        public string type;
        public QuestClauseItem[] items;
        public QuestClausePack packs;
    }
}
