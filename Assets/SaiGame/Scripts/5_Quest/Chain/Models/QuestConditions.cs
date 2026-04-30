using System;

namespace SaiGame.Services
{
    /// <summary>
    /// The conditions block of a quest definition.
    /// </summary>
    [Serializable]
    public class QuestConditions
    {
        public string operator_type; // mapped manually; JSON key is "operator"
        public QuestClause[] clauses;
    }
}
