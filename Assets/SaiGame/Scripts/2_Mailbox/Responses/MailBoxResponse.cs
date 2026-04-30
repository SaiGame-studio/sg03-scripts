using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Represents the response from the mailbox messages API.
    /// </summary>
    [Serializable]
    public class MailBoxResponse
    {
        public MailboxMessage[] messages;
        public int total;
    }
}
