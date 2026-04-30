using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Represents a single message in the mailbox.
    /// </summary>
    [Serializable]
    public class MailboxMessage
    {
        public string id;
        public string sender_id;
        public string subject;
        public string body;
        public string message_type;
        public string status;
        public MailBoxAttachment[] attachments;
        public string expires_at;
        public string read_at;
        public string claimed_at;
        public string created_at;
    }
}
