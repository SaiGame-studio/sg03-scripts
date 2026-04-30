using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Response model for read message operation.
    /// </summary>
    [Serializable]
    public class ReadMessageResponse
    {
        public MailboxMessage message;
        public string message_text;
    }
}
