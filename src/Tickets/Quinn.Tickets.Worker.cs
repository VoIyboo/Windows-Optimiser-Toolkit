using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

[assembly: AssemblyTitle("Quinn Ticket Worker")]
[assembly: AssemblyDescription("Background ticket reply worker for Quinn Optimiser Toolkit Outlook sending.")]
[assembly: AssemblyCompany("Quinn Optimiser Toolkit")]
[assembly: AssemblyProduct("Quinn Optimiser Toolkit")]
[assembly: AssemblyCopyright("Copyright (c) Quinn Optimiser Toolkit")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: AssemblyInformationalVersion("1.0.0")]

namespace Quinn.Tickets.Worker
{
    [DataContract]
    internal sealed class SendReplyPayload
    {
        [DataMember] public string TicketId;
        [DataMember] public string PendingReplyDraftId;
        [DataMember] public string Subject;
        [DataMember] public string Body;
        [DataMember] public string To;
        [DataMember] public string SenderMailbox;
        [DataMember] public string SourceMessageId;
        [DataMember] public string SourceStoreId;
        [DataMember] public string EmailMessageId;
    }

    [DataContract]
    internal sealed class SendReplyResult
    {
        [DataMember] public bool Success;
        [DataMember] public string Note;
        [DataMember] public string TicketId;
        [DataMember] public string PendingReplyDraftId;
        [DataMember] public string ConversationId;
        [DataMember] public string SentEntryId;
        [DataMember] public string SentStoreId;
        [DataMember] public string ErrorType;
    }

    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            var result = new SendReplyResult
            {
                Success = false,
                Note = "Worker did not complete.",
                ErrorType = "Startup"
            };
            string resultPath = string.Empty;

            try
            {
                if (args == null || args.Length == 0)
                {
                    throw new InvalidOperationException("Worker command is required.");
                }

                var command = (args[0] ?? string.Empty).Trim();
                var options = ParseOptions(args);
                if (string.Equals(command, "test-outlook", StringComparison.OrdinalIgnoreCase))
                {
                    resultPath = GetOptionalOption(options, "result");
                    Log("Worker Outlook diagnostic starting. ResultPath='" + resultPath + "'.");
                    result = ExecuteOutlookDiagnosticOnStaThread(result);
                    Log("Worker Outlook diagnostic completed. Success=" + result.Success + " Note='" + SafeTrim(result.Note) + "'.");
                }
                else if (string.Equals(command, "send-reply", StringComparison.OrdinalIgnoreCase))
                {
                    var payloadPath = GetRequiredOption(options, "payload");
                    resultPath = GetRequiredOption(options, "result");

                    Log("Worker starting. PayloadPath='" + payloadPath + "' ResultPath='" + resultPath + "'.");
                    var payload = ReadJson<SendReplyPayload>(payloadPath);
                    if (payload == null)
                    {
                        throw new InvalidOperationException("Reply payload was empty.");
                    }

                    result.TicketId = SafeTrim(payload.TicketId);
                    result.PendingReplyDraftId = SafeTrim(payload.PendingReplyDraftId);
                    result = ExecuteSendOnStaThread(payload, result);
                    Log("Worker completed. Success=" + result.Success + " TicketId='" + SafeTrim(result.TicketId) + "' Note='" + SafeTrim(result.Note) + "'.");
                }
                else
                {
                    throw new InvalidOperationException("Unsupported worker command: " + command);
                }
            }
            catch (Exception ex)
            {
                result.Success = false;
                result.ErrorType = "WorkerFailure";
                result.Note = "Worker failed: " + ex.Message;
                Log("Worker failed. " + ex, "ERROR");
            }

            try
            {
                if (!string.IsNullOrWhiteSpace(resultPath))
                {
                    WriteJson(resultPath, result);
                }
            }
            catch (Exception ex)
            {
                Log("Failed to write result file. " + ex, "ERROR");
                return 1;
            }

            return result.Success ? 0 : 1;
        }

        private static SendReplyResult ExecuteSendOnStaThread(SendReplyPayload payload, SendReplyResult seed)
        {
            SendReplyResult result = seed;
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try
                {
                    result = SendReply(payload);
                }
                catch (Exception ex)
                {
                    failure = ex;
                }
            });

            thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            thread.Join();

            if (failure != null)
            {
                throw failure;
            }

            return result;
        }

        private static SendReplyResult ExecuteOutlookDiagnosticOnStaThread(SendReplyResult seed)
        {
            SendReplyResult result = seed;
            Exception failure = null;
            var thread = new Thread(() =>
            {
                dynamic outlookApp = null;
                dynamic mapi = null;
                try
                {
                    mapi = GetOutlookNamespace(out outlookApp);
                    var profileName = SafeGetString(() => mapi.CurrentProfileName);
                    result = new SendReplyResult
                    {
                        Success = true,
                        Note = "Outlook COM ready. Profile='" + profileName + "'.",
                        ErrorType = string.Empty,
                        TicketId = string.Empty,
                        PendingReplyDraftId = string.Empty,
                        ConversationId = string.Empty,
                        SentEntryId = string.Empty,
                        SentStoreId = string.Empty
                    };
                }
                catch (Exception ex)
                {
                    result = new SendReplyResult
                    {
                        Success = false,
                        Note = "Outlook diagnostic failed: " + ex.Message,
                        ErrorType = "OutlookUnavailable",
                        TicketId = string.Empty,
                        PendingReplyDraftId = string.Empty,
                        ConversationId = string.Empty,
                        SentEntryId = string.Empty,
                        SentStoreId = string.Empty
                    };
                }
                finally
                {
                    ReleaseComObject(mapi);
                    ReleaseComObject(outlookApp);
                }
            });

            thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            thread.Join();

            if (failure != null)
            {
                throw failure;
            }

            return result;
        }

        private static SendReplyResult SendReply(SendReplyPayload payload)
        {
            var subject = SafeTrim(payload.Subject);
            var body = (payload.Body ?? string.Empty).Trim();
            var to = SafeTrim(payload.To);
            var senderMailbox = SafeTrim(payload.SenderMailbox);
            var sourceMessageId = SafeTrim(payload.SourceMessageId);
            var sourceStoreId = SafeTrim(payload.SourceStoreId);
            var emailMessageId = NormalizeInternetMessageId(payload.EmailMessageId);

            if (string.IsNullOrWhiteSpace(subject))
            {
                return Failure(payload, "Reply subject required.", "Validation");
            }

            if (string.IsNullOrWhiteSpace(body))
            {
                return Failure(payload, "Reply body required.", "Validation");
            }

            var mutexName = "Local\\QuinnTicketsOutlookSend";
            bool lockTaken = false;
            Mutex sendMutex = null;
            try
            {
                sendMutex = new Mutex(false, mutexName);
                try
                {
                    lockTaken = sendMutex.WaitOne(TimeSpan.FromMinutes(5), false);
                }
                catch (AbandonedMutexException)
                {
                    lockTaken = true;
                }

                if (!lockTaken)
                {
                    return Failure(payload, "Reply send is already busy. Please retry shortly.", "WorkerBusy");
                }

                dynamic outlookApp = null;
                dynamic mapi = null;
                try
                {
                    mapi = GetOutlookNamespace(out outlookApp);
                }
                catch (Exception ex)
                {
                    return Failure(payload, "Unable to send reply: " + ex.Message, "OutlookUnavailable");
                }

                try
                {
                    if (!string.IsNullOrWhiteSpace(sourceMessageId) || !string.IsNullOrWhiteSpace(emailMessageId))
                    {
                        dynamic mailItem = null;
                        if (!string.IsNullOrWhiteSpace(sourceMessageId))
                        {
                            try
                            {
                                mailItem = string.IsNullOrWhiteSpace(sourceStoreId)
                                    ? mapi.GetItemFromID(sourceMessageId)
                                    : mapi.GetItemFromID(sourceMessageId, sourceStoreId);
                            }
                            catch
                            {
                                mailItem = null;
                            }
                        }

                        if (mailItem == null && !string.IsNullOrWhiteSpace(emailMessageId))
                        {
                            mailItem = FindMessageByInternetId(mapi, emailMessageId, 300);
                        }

                        if (mailItem != null)
                        {
                            return SendAsReply(payload, mapi, mailItem, senderMailbox);
                        }

                        if (string.IsNullOrWhiteSpace(to))
                        {
                            return Failure(payload, "Original email not found in Outlook.", "OriginalMessageMissing");
                        }

                        Log("Original message not found; falling back to outbound email.");
                    }

                    if (string.IsNullOrWhiteSpace(to))
                    {
                        return Failure(payload, "Ticket has no customer email address.", "Validation");
                    }

                    return SendAsNewEmail(payload, outlookApp, mapi, to, senderMailbox);
                }
                finally
                {
                    ReleaseComObject(mapi);
                    ReleaseComObject(outlookApp);
                }
            }
            finally
            {
                if (lockTaken && sendMutex != null)
                {
                    try { sendMutex.ReleaseMutex(); } catch { }
                }

                if (sendMutex != null)
                {
                    try { sendMutex.Dispose(); } catch { }
                }
            }
        }

        private static SendReplyResult SendAsReply(SendReplyPayload payload, dynamic mapi, dynamic mailItem, string senderMailbox)
        {
            try
            {
                return TrySendReply(payload, mapi, mailItem, senderMailbox, plainTextOnly: false);
            }
            catch (Exception ex)
            {
                var primaryFailure = SafeTrim(ex.Message);
                if (Regex.IsMatch(primaryFailure, "Value does not fall within the expected range", RegexOptions.IgnoreCase))
                {
                    Log("Reply rich-mode failed; retrying plain text. " + primaryFailure, "WARN");
                    try
                    {
                        return TrySendReply(payload, mapi, mailItem, senderMailbox, plainTextOnly: true);
                    }
                    catch (Exception retryEx)
                    {
                        return Failure(payload, "Reply failed: " + SafeTrim(retryEx.Message), "SendFailure");
                    }
                }

                if ((primaryFailure.IndexOf("cannot be found", StringComparison.OrdinalIgnoreCase) >= 0 ||
                     primaryFailure.IndexOf("MAPI_E_NOT_FOUND", StringComparison.OrdinalIgnoreCase) >= 0) &&
                    !string.IsNullOrWhiteSpace(payload.To))
                {
                    Log("Reply source disappeared during send; falling back to outbound email. " + primaryFailure, "WARN");
                    return SendAsNewEmail(payload, null, mapi, SafeTrim(payload.To), senderMailbox);
                }

                return Failure(payload, "Reply failed: " + primaryFailure, "SendFailure");
            }
            finally
            {
                ReleaseComObject(mailItem);
            }
        }

        private static SendReplyResult TrySendReply(SendReplyPayload payload, dynamic mapi, dynamic mailItem, string senderMailbox, bool plainTextOnly)
        {
            dynamic reply = null;
            try
            {
                reply = mailItem.Reply();
                if (reply == null)
                {
                    throw new InvalidOperationException("Outlook did not return a reply item.");
                }

                if (!string.IsNullOrWhiteSpace(payload.Subject))
                {
                    TrySet(() => reply.Subject = payload.Subject);
                }

                var usedHtml = false;
                if (!plainTextOnly)
                {
                    TrySet(() => reply.BodyFormat = 2);
                    var existingHtml = SafeGetString(() => reply.HTMLBody);
                    if (!string.IsNullOrWhiteSpace(existingHtml))
                    {
                        reply.HTMLBody = ConvertPlainTextToHtml(payload.Body) + "<br/>" + existingHtml;
                        usedHtml = true;
                    }
                }

                if (!usedHtml)
                {
                    var existingBody = SafeGetString(() => reply.Body);
                    reply.Body = (payload.Body ?? string.Empty) + "\r\n\r\n" + existingBody;
                }

                if (!string.IsNullOrWhiteSpace(senderMailbox))
                {
                    SetSender(reply, mapi, senderMailbox);
                }

                reply.Send();
                return Success(payload, "Reply sent.", reply);
            }
            finally
            {
                ReleaseComObject(reply);
            }
        }

        private static SendReplyResult SendAsNewEmail(SendReplyPayload payload, dynamic outlookApp, dynamic mapi, string to, string senderMailbox)
        {
            dynamic mail = null;
            dynamic localApp = outlookApp;
            try
            {
                if (localApp == null)
                {
                    localApp = GetOutlookApplication();
                }

                mail = localApp.CreateItem(0);
                mail.To = to;
                mail.Subject = payload.Subject;
                TrySet(() => mail.BodyFormat = 1);
                mail.Body = payload.Body ?? string.Empty;

                if (!string.IsNullOrWhiteSpace(senderMailbox))
                {
                    SetSender(mail, mapi, senderMailbox);
                }

                mail.Send();
                return Success(payload, "Email sent.", mail);
            }
            catch (Exception ex)
            {
                return Failure(payload, "Email send failed: " + SafeTrim(ex.Message), "SendFailure");
            }
            finally
            {
                ReleaseComObject(mail);
                if (!ReferenceEquals(localApp, outlookApp))
                {
                    ReleaseComObject(localApp);
                }
            }
        }

        private static dynamic GetOutlookNamespace(out dynamic outlookApp)
        {
            outlookApp = null;
            Exception lastFailure = null;

            Log("Resolving Outlook COM. Is64BitProcess=" + Environment.Is64BitProcess + " UserInteractive=" + Environment.UserInteractive + " SessionId=" + Process.GetCurrentProcess().SessionId + ".");

            for (var attempt = 1; attempt <= 4; attempt++)
            {
                if (TryGetActiveOutlookApplication(out outlookApp, out lastFailure))
                {
                    Log("Attached to existing Outlook.Application instance on attempt " + attempt + ".");
                    break;
                }

                Log("Active Outlook attach attempt " + attempt + " failed. " + SafeTrim(lastFailure == null ? string.Empty : lastFailure.Message), attempt == 1 ? "INFO" : "WARN");
                Thread.Sleep(750 * attempt);
            }

            if (outlookApp == null)
            {
                StartOutlookNormally();

                var deadline = DateTime.UtcNow.AddSeconds(45);
                var attempt = 0;
                while (DateTime.UtcNow < deadline)
                {
                    attempt++;
                    if (TryGetActiveOutlookApplication(out outlookApp, out lastFailure))
                    {
                        Log("Attached to Outlook.Application after launching Outlook. Attempt=" + attempt + ".");
                        break;
                    }

                    Thread.Sleep(1500);
                }
            }

            if (outlookApp == null)
            {
                try
                {
                    outlookApp = CreateOutlookApplication();
                    Log("Created Outlook.Application COM instance after attach/startup attempts.", "WARN");
                }
                catch (Exception ex)
                {
                    lastFailure = ex;
                }
            }

            if (outlookApp == null)
            {
                var detail = lastFailure == null ? string.Empty : " Last error: " + lastFailure.Message;
                throw new InvalidOperationException("Classic Outlook is unavailable to the worker. Open Classic Outlook fully in this Windows session, dismiss any profile/first-run prompts, then retry." + detail);
            }

            dynamic mapi = null;
            Exception namespaceFailure = null;
            for (var attempt = 1; attempt <= 8; attempt++)
            {
                try
                {
                    mapi = outlookApp.GetNamespace("MAPI");
                    if (mapi != null)
                    {
                        TryInvoke(() => mapi.Logon("", "", false, false));
                        var profileName = SafeGetString(() => mapi.CurrentProfileName);
                        Log("Outlook MAPI namespace ready. Profile='" + profileName + "' Attempt=" + attempt + ".");
                        break;
                    }
                }
                catch (Exception ex)
                {
                    namespaceFailure = ex;
                }

                Thread.Sleep(1500);
            }

            if (mapi == null)
            {
                var detail = namespaceFailure == null ? string.Empty : " Last error: " + namespaceFailure.Message;
                throw new InvalidOperationException("Outlook MAPI namespace unavailable." + detail);
            }

            return mapi;
        }

        private static dynamic GetOutlookApplication()
        {
            dynamic app = null;
            Exception failure = null;
            if (TryGetActiveOutlookApplication(out app, out failure))
            {
                return app;
            }

            StartOutlookNormally();
            var deadline = DateTime.UtcNow.AddSeconds(30);
            while (DateTime.UtcNow < deadline)
            {
                if (TryGetActiveOutlookApplication(out app, out failure))
                {
                    return app;
                }

                Thread.Sleep(1000);
            }

            return CreateOutlookApplication();
        }

        private static bool TryGetActiveOutlookApplication(out dynamic outlookApp, out Exception failure)
        {
            outlookApp = null;
            failure = null;
            try
            {
                outlookApp = Marshal.GetActiveObject("Outlook.Application");
                return outlookApp != null;
            }
            catch (Exception ex)
            {
                failure = ex;
                outlookApp = null;
                return false;
            }
        }

        private static dynamic CreateOutlookApplication()
        {
            var outlookType = Type.GetTypeFromProgID("Outlook.Application", true);
            if (outlookType == null)
            {
                throw new InvalidOperationException("Classic Outlook is not available on this machine.");
            }

            return Activator.CreateInstance(outlookType);
        }

        private static void StartOutlookNormally()
        {
            var outlookPath = FindOutlookExecutablePath();
            if (string.IsNullOrWhiteSpace(outlookPath))
            {
                Log("Outlook executable path was not found in registry or common Office folders.", "WARN");
                return;
            }

            try
            {
                Log("Starting Outlook for COM attach. Path='" + outlookPath + "'.");
                var startInfo = new ProcessStartInfo
                {
                    FileName = outlookPath,
                    Arguments = "/recycle",
                    UseShellExecute = true,
                    WindowStyle = ProcessWindowStyle.Minimized
                };
                using (var process = Process.Start(startInfo))
                {
                    if (process != null)
                    {
                        try { process.WaitForInputIdle(12000); } catch { }
                    }
                }
            }
            catch (Exception ex)
            {
                Log("Starting Outlook failed. " + ex.Message, "WARN");
            }
        }

        private static string FindOutlookExecutablePath()
        {
            foreach (var candidate in new[]
            {
                ReadRegistryDefault(@"HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{0006F03A-0000-0000-C000-000000000046}\LocalServer32"),
                ReadRegistryDefault(@"HKEY_CLASSES_ROOT\CLSID\{0006F03A-0000-0000-C000-000000000046}\LocalServer32"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft Office\root\Office16\OUTLOOK.EXE"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft Office\root\Office16\OUTLOOK.EXE")
            })
            {
                var path = ExtractExecutablePath(candidate);
                if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
                {
                    return path;
                }
            }

            return string.Empty;
        }

        private static string ReadRegistryDefault(string keyName)
        {
            try
            {
                var value = Microsoft.Win32.Registry.GetValue(keyName, string.Empty, string.Empty);
                return value == null ? string.Empty : Convert.ToString(value);
            }
            catch
            {
                return string.Empty;
            }
        }

        private static string ExtractExecutablePath(string value)
        {
            var text = SafeTrim(value);
            if (text.Length == 0)
            {
                return string.Empty;
            }

            if (text[0] == '"')
            {
                var end = text.IndexOf('"', 1);
                if (end > 1)
                {
                    return text.Substring(1, end - 1);
                }
            }

            var exeIndex = text.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            if (exeIndex >= 0)
            {
                return text.Substring(0, exeIndex + 4).Trim();
            }

            return text;
        }

        private static dynamic FindMessageByInternetId(dynamic mapi, string internetMessageId, int maxScan)
        {
            if (mapi == null || string.IsNullOrWhiteSpace(internetMessageId))
            {
                return null;
            }

            var target = NormalizeInternetMessageId(internetMessageId);
            var visited = 0;
            dynamic stores = null;

            try
            {
                stores = mapi.Stores;
                foreach (var store in ToEnumerable(stores))
                {
                    dynamic rootFolder = null;
                    try
                    {
                        rootFolder = store.GetRootFolder();
                        var found = FindMessageByInternetIdInFolder(rootFolder, target, maxScan, ref visited);
                        if (found != null)
                        {
                            return found;
                        }
                    }
                    finally
                    {
                        ReleaseComObject(rootFolder);
                        ReleaseComObject(store);
                    }
                }
            }
            finally
            {
                ReleaseComObject(stores);
            }

            return null;
        }

        private static dynamic FindMessageByInternetIdInFolder(dynamic folder, string target, int maxScan, ref int visited)
        {
            if (folder == null || visited >= maxScan)
            {
                return null;
            }

            dynamic items = null;
            try
            {
                items = folder.Items;
                TryInvoke(() => items.Sort("[ReceivedTime]", true));
                foreach (var item in ToEnumerable(items))
                {
                    try
                    {
                        if (visited >= maxScan)
                        {
                            return null;
                        }

                        visited++;
                        var messageClass = SafeGetString(() => item.MessageClass);
                        if (messageClass.IndexOf("IPM.Note", StringComparison.OrdinalIgnoreCase) != 0)
                        {
                            continue;
                        }

                        var internetId = NormalizeInternetMessageId(SafeGetString(() =>
                            item.PropertyAccessor.GetProperty("http://schemas.microsoft.com/mapi/string/{00020386-0000-0000-C000-000000000046}/InternetMessageId")));
                        if (string.Equals(internetId, target, StringComparison.OrdinalIgnoreCase))
                        {
                            return item;
                        }
                    }
                    catch
                    {
                    }

                    ReleaseComObject(item);
                }
            }
            finally
            {
                ReleaseComObject(items);
            }

            dynamic folders = null;
            try
            {
                folders = folder.Folders;
                foreach (var child in ToEnumerable(folders))
                {
                    try
                    {
                        var found = FindMessageByInternetIdInFolder(child, target, maxScan, ref visited);
                        if (found != null)
                        {
                            return found;
                        }
                    }
                    finally
                    {
                        ReleaseComObject(child);
                    }
                }
            }
            finally
            {
                ReleaseComObject(folders);
            }

            return null;
        }

        private static void SetSender(dynamic mailItem, dynamic mapi, string mailboxAddress)
        {
            if (mailItem == null || mapi == null || string.IsNullOrWhiteSpace(mailboxAddress))
            {
                return;
            }

            var target = SafeTrim(mailboxAddress);
            dynamic session = null;
            dynamic accounts = null;
            try
            {
                session = mapi.Session;
                accounts = session.Accounts;
                foreach (var account in ToEnumerable(accounts))
                {
                    try
                    {
                        var smtp = SafeTrim(SafeGetString(() => account.SmtpAddress));
                        var displayName = SafeTrim(SafeGetString(() => account.DisplayName));
                        if (string.Equals(smtp, target, StringComparison.OrdinalIgnoreCase) ||
                            string.Equals(displayName, target, StringComparison.OrdinalIgnoreCase))
                        {
                            TrySet(() => mailItem.SendUsingAccount = account);
                            return;
                        }
                    }
                    finally
                    {
                        ReleaseComObject(account);
                    }
                }
            }
            finally
            {
                ReleaseComObject(accounts);
                ReleaseComObject(session);
            }

            TrySet(() => mailItem.SentOnBehalfOfName = target);
        }

        private static SendReplyResult Success(SendReplyPayload payload, string note, dynamic sentItem)
        {
            var result = new SendReplyResult
            {
                Success = true,
                Note = note,
                TicketId = SafeTrim(payload.TicketId),
                PendingReplyDraftId = SafeTrim(payload.PendingReplyDraftId),
                ConversationId = SafeTrim(SafeGetString(() => sentItem.ConversationID)),
                SentEntryId = SafeTrim(SafeGetString(() => sentItem.EntryID)),
                ErrorType = string.Empty
            };

            try
            {
                result.SentStoreId = SafeTrim(SafeGetString(() => sentItem.Parent.StoreID));
            }
            catch
            {
                result.SentStoreId = string.Empty;
            }

            return result;
        }

        private static SendReplyResult Failure(SendReplyPayload payload, string note, string errorType)
        {
            return new SendReplyResult
            {
                Success = false,
                Note = note,
                ErrorType = errorType,
                TicketId = SafeTrim(payload.TicketId),
                PendingReplyDraftId = SafeTrim(payload.PendingReplyDraftId),
                ConversationId = string.Empty,
                SentEntryId = string.Empty,
                SentStoreId = string.Empty
            };
        }

        private static Dictionary<string, string> ParseOptions(string[] args)
        {
            var options = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (var i = 1; i < args.Length; i++)
            {
                var key = SafeTrim(args[i]);
                if (!key.StartsWith("--", StringComparison.Ordinal))
                {
                    continue;
                }

                key = key.Substring(2);
                var value = string.Empty;
                if (i + 1 < args.Length)
                {
                    value = args[i + 1] ?? string.Empty;
                    i++;
                }

                options[key] = value;
            }

            return options;
        }

        private static string GetRequiredOption(IDictionary<string, string> options, string name)
        {
            string value;
            if (!options.TryGetValue(name, out value) || string.IsNullOrWhiteSpace(value))
            {
                throw new InvalidOperationException("Missing required option --" + name + ".");
            }

            return value;
        }

        private static string GetOptionalOption(IDictionary<string, string> options, string name)
        {
            string value;
            return options.TryGetValue(name, out value) ? SafeTrim(value) : string.Empty;
        }

        private static T ReadJson<T>(string path)
        {
            var json = File.ReadAllText(path, Encoding.UTF8);
            if (!string.IsNullOrEmpty(json) && json.Length > 0 && json[0] == '\uFEFF')
            {
                json = json.Substring(1);
            }

            using (var stream = new MemoryStream(Encoding.UTF8.GetBytes(json)))
            {
                var serializer = new DataContractJsonSerializer(typeof(T));
                return (T)serializer.ReadObject(stream);
            }
        }

        private static void WriteJson<T>(string path, T value)
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            using (var stream = File.Create(path))
            {
                var serializer = new DataContractJsonSerializer(typeof(T));
                serializer.WriteObject(stream, value);
            }
        }

        private static IEnumerable ToEnumerable(object comCollection)
        {
            var enumerable = comCollection as IEnumerable;
            return enumerable ?? new object[0];
        }

        private static string SafeTrim(string value)
        {
            return (value ?? string.Empty).Trim();
        }

        private static string NormalizeInternetMessageId(string value)
        {
            var normalized = SafeTrim(value);
            if (normalized.Length == 0)
            {
                return string.Empty;
            }

            return normalized.Replace("\r", string.Empty).Replace("\n", string.Empty);
        }

        private static string ConvertPlainTextToHtml(string text)
        {
            var normalized = (text ?? string.Empty).Replace("\r\n", "\n").Replace("\r", "\n");
            var encoded = System.Security.SecurityElement.Escape(normalized) ?? string.Empty;
            return encoded.Replace("\n", "<br/>");
        }

        private static string SafeGetString(Func<object> getter)
        {
            try
            {
                var value = getter();
                return value == null ? string.Empty : Convert.ToString(value) ?? string.Empty;
            }
            catch
            {
                return string.Empty;
            }
        }

        private static void TrySet(Action action)
        {
            try
            {
                action();
            }
            catch
            {
            }
        }

        private static void TryInvoke(Action action)
        {
            try
            {
                action();
            }
            catch
            {
            }
        }

        private static void ReleaseComObject(object value)
        {
            if (value == null || !Marshal.IsComObject(value))
            {
                return;
            }

            try
            {
                Marshal.FinalReleaseComObject(value);
            }
            catch
            {
            }
        }

        private static void Log(string message, string level = "INFO")
        {
            try
            {
                var logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "QuinnOptimiserToolkit", "Logs");
                Directory.CreateDirectory(logDir);
                var logPath = Path.Combine(logDir, "TicketsWorker.log");
                File.AppendAllText(logPath, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}{3}", DateTime.Now, level, message, Environment.NewLine), Encoding.UTF8);
            }
            catch
            {
            }
        }
    }
}
