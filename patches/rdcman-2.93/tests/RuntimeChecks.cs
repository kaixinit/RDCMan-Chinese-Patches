// Project-authored verification harness. It never calls RDCMan.Program.Main or opens a window.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Xml;

internal static class RuntimeChecks
{
    private static readonly List<object> Results = new List<object>();
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
    private static void Record(string name) { Results.Add(new { Name = name, Passed = true }); }
    private static int Main(string[] args)
    {
        try
        {
            Require(args.Length == 2, "Expected an executable path and a report path.");
            byte[] bytes = File.ReadAllBytes(args[0]);
            string digest;
            using (SHA256 hash = SHA256.Create())
                digest = BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-", "");
            Assembly assembly = Assembly.Load(bytes);
            Require(assembly.GetName().Version.ToString() == "2.93.1431.0", "Unexpected target version.");
            Type helper = assembly.GetType("RdcMan.ChineseStudyText", true);
            BindingFlags staticFlags = BindingFlags.Static | BindingFlags.NonPublic;
            string[][] cases = {
                new [] {"Caption", "Left", "左侧"},
                new [] {"Caption", "Dock", "停靠"},
                new [] {"Caption", "AutoHide", "自动隐藏"},
                new [] {"Caption", "ServerName", "服务器名称"},
                new [] {"Caption", "DoesNotMatch", "不匹配"},
                new [] {"Caption", "my-server", "my-server"},
                new [] {"Caption", "Remote Desktop Connection Manager", "远程桌面连接管理器"},
                new [] {"CanonicalGroupKey", "收藏夹", "Favorites"},
                new [] {"CanonicalGroupKey", "已连接", "Connected"},
                new [] {"CanonicalGroupKey", "待重连", "Reconnect"},
                new [] {"CanonicalGroupKey", "最近使用", "Recent"},
                new [] {"CanonicalGroupKey", "Favorites", "Favorites"},
                new [] {"CanonicalGroupKey", "用户分组", "用户分组"},
                new [] {"TitleCaption", "远程桌面连接管理器（中文学习版）", "远程桌面连接管理器"},
                new [] {"TitleCaption", "用户分组（中文学习版）", "用户分组（中文学习版）"}
            };
            foreach (string[] item in cases)
            {
                MethodInfo method = helper.GetMethod(item[0], staticFlags);
                Require((string)method.Invoke(null, new object[] { item[1] }) == item[2], "Caption mismatch: " + item[0]);
                Record(item[0] + ":" + item[1]);
            }
            object profile = FormatterServices.GetUninitializedObject(assembly.GetType("RdcMan.CredentialsProfile", true));
            MethodInfo profileMap = helper.GetMethod("ProfileCaption", staticFlags);
            Require((string)profileMap.Invoke(null, new [] { "Custom", profile }) == "自定义", "Default profile caption mismatch.");
            Record("Custom-profile display");
            Require((string)profileMap.Invoke(null, new object[] { "Custom", new object() }) == "Custom", "Non-profile content changed.");
            Record("Non-profile user text preserved");
            Require((string)profileMap.Invoke(null, new [] { "用户凭据", profile }) == "用户凭据", "User profile name changed.");
            Record("User profile name preserved");

            BindingFlags instanceFlags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
            string[][] types = {
                new [] { "RdcMan.Server", "服务器" },
                new [] { "RdcMan.FavoriteServerRef", "服务器引用" }
            };
            foreach (string[] item in types)
            {
                Type type = assembly.GetType(item[0], true);
                object instance = FormatterServices.GetUninitializedObject(type);
                Require((string)type.GetProperty("RemoveTypeDescription", instanceFlags).GetValue(instance, null) == item[1], "Removal caption mismatch.");
                Record(item[0] + ".RemoveTypeDescription");
            }
            string[] documents = {
                "<connectionSettings inherit=\"InvalidMode\" />",
                "<connectionSettings />",
                "<connectionSettings inherit=\"99\" />"
            };
            foreach (string source in documents)
            {
                object settings = Activator.CreateInstance(assembly.GetType("RdcMan.ConnectionSettings", true), true);
                XmlDocument document = new XmlDocument();
                document.LoadXml(source);
                string before = document.OuterXml;
                List<string> errors = new List<string>();
                settings.GetType().GetMethod("ReadXml", instanceFlags).Invoke(settings, new object[] { document.DocumentElement, null, errors });
                Require(errors.Count == 1 && errors[0].Contains("继承模式") && !errors[0].Contains("Unexpected") && !errors[0].Contains("No inheritance"), "Parser warning is missing or untranslated.");
                Require(before == document.OuterXml, "Input XML was modified.");
                Record("XML warning and identifiers: " + source);
            }
            MethodInfo expand = assembly.GetType("RdcMan.StringUtilities", true).GetMethod("ExpandPattern", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
            foreach (string[] item in new [] {
                new [] { "audit-[1-2].invalid", "audit-1.invalid,audit-2.invalid" },
                new [] { "audit-[a-b].invalid", "audit-a.invalid,audit-b.invalid" }
            })
            {
                List<string> names = new List<string>();
                foreach (object name in (IEnumerable)expand.Invoke(null, new object[] { item[0] })) names.Add((string)name);
                Require(string.Join(",", names.ToArray()) == item[1], "Valid expansion changed.");
                Record("Valid import range: " + item[0]);
            }
            foreach (string[] item in new [] {
                new [] { "audit-[3-1].invalid", "范围起始值不能大于结束值：3-1" },
                new [] { "audit-[1-2.invalid", "范围缺少结束符" },
                new [] { "audit-[1-b].invalid", "范围起止值必须同为字母或数字" }
            })
            {
                bool rejected = false;
                try { foreach (object unused in (IEnumerable)expand.Invoke(null, new object[] { item[0] })) { } }
                catch (ArgumentException exception) { rejected = exception.Message.Contains(item[1]); }
                Require(rejected, "Invalid range was accepted or its error is untranslated.");
                Record("Chinese import range error: " + item[0]);
            }
            Require(Results.Count == 28, "Unexpected case count.");
            object report = new {
                Passed = true, Cases = Results.Count, TargetVersion = assembly.GetName().Version.ToString(),
                TargetSHA256 = digest, Runtime = Environment.Version.ToString(), NoApplicationStarted = true, Results = Results
            };
            File.WriteAllText(args[1], new JavaScriptSerializer().Serialize(report), new UTF8Encoding(false));
            Console.WriteLine("Runtime checks passed: " + Results.Count);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.ToString());
            return 1;
        }
    }
}
