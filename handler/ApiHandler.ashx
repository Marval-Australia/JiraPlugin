﻿<%@ WebHandler Language="C#" Class="ApiHandler" %>

using System;
using System.IO;
using System.Net;
using System.Text;
using System.Web;
using System.Dynamic;
using System.Collections.Generic;
using System.Globalization;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using MarvalSoftware;
using MarvalSoftware.UI.WebUI.ServiceDesk.RFP.Plugins;
using MarvalSoftware.ServiceDesk.Facade;
using MarvalSoftware.DataTransferObjects;
using System.Threading.Tasks;
using System.Linq;
using Serilog;

public static class ObjectExtensions
{
    public static bool HasProperty(this object obj, string propertyName)
    {
        return obj.GetType().GetProperty(propertyName) != null;
    }
}

/// <summary>
/// ApiHandler
/// </summary>
public class ApiHandler : PluginHandler
{

    
    //properties
    private string CustomFieldName
    {
        get
        {
            return this.GlobalSettings["@@JIRACustomFieldName"];
        }
    }


    private string BaseUrl
    {
        get
        {
            return this.GlobalSettings["@@JIRABaseUrl"];
        }
    }
    
public class FormDetails
{
    public string Name { get; set; }
    // Add other properties as needed
}

public class Response
{
    public List<FormDetails> Forms { get; set; }
    // Add other properties as needed
}

    private string ApiBaseUrl
    {
        get
        {
            return this.BaseUrl + "rest/api/latest/";
        }
    }

    public class FormField
    {
    public string Name { get; set; }
    public object Value { get; set; }
    }

public class FormFieldSet
{
    public List<FormField> Fields { get; set; }
}

public class Form
{
    public List<FormFieldSet> FieldSets { get; set; }
}

    private string MSMBaseUrl
    {
        get
        {
            return HttpContext.Current.Request.Url.Scheme + "://" + HttpContext.Current.Request.Url.Host + MarvalSoftware.UI.WebUI.ServiceDesk.WebHelper.ApplicationPath;
        }
    }
    private string CustomFieldId { get; set; }
    private string MsmApiKey
    {
        get
        {
            return this.GlobalSettings["@@MSMAPIKey"];
        }
    }

    private string Username
    {
        get
        {
            return this.GlobalSettings["@@JIRAUsername"];
        }
    }

    private string Password
    {
        get
        {
            return this.GlobalSettings["@@JIRAPassword"];
        }
    }

    private string JiraCredentials
    {
        get
        {
            return ApiHandler.GetEncodedCredentials(string.Format("{0}:{1}", this.Username, this.Password));
        }
    }

    private IWebProxy Proxy
    {
        get
        {
            IWebProxy proxy = System.Net.WebRequest.GetSystemWebProxy();
            if (proxy != null && this.ProxyCredentials != null)
            {
                proxy.Credentials = this.ProxyCredentials;
            }
            return proxy;
        }
    }

    private string ProxyUsername
    {
        get
        {
            return GlobalSettings["@@ProxyUsername"];
        }
    }
  
    private string ProxyPassword
    {
        get
        {
            return GlobalSettings["@@ProxyPassword"];
        }
    }

    private ICredentials ProxyCredentials
    {
        get
        {
            if (String.IsNullOrWhiteSpace(this.ProxyUsername))
                return null;
            return new NetworkCredential(this.ProxyUsername, this.ProxyPassword);
        }
    }
    private string JIRAFieldType { get; set; }
    private string JIRAFieldID { get; set; }
    private string JiraIssueNo { get; set; }

    private string JiraSummary { get; set; }

    private string JiraType { get; set; }

    private string JiraProject { get; set; }

    private string JiraReporter { get; set; }

    private string AttachmentIds { get; set; }

    private string MsmContactEmail { get; set; }

    private string IssueUrl { get; set; }

    //fields
    private int msmRequestNo;
    private static readonly int second = 1;
    private static readonly int minute = 60 * ApiHandler.second;
    private static readonly int hour = 60 * ApiHandler.minute;
    private static readonly int day = 24 * ApiHandler.hour;

    /// <summary>
    /// Handle Request
    /// </summary>
    public override void HandleRequest(HttpContext context)
    {
        this.ProcessParamaters(context.Request);

        var action = context.Request.QueryString["action"];
        this.RouteRequest(action, context);
    }

    public override bool IsReusable
    {
        get { return false; }
    }

    /// <summary>
    /// Get Paramaters from QueryString
    /// </summary>
    private void ProcessParamaters(HttpRequest httpRequest)
    {
        int.TryParse(httpRequest.Params["requestNumber"], out this.msmRequestNo);
        this.JiraIssueNo = httpRequest.Params["issueNumber"] ?? string.Empty;
        this.JiraSummary = httpRequest.Params["issueSummary"] ?? string.Empty;
        this.JiraType = httpRequest.Params["issueType"] ?? string.Empty;
        this.JiraProject = httpRequest.Params["project"] ?? string.Empty;
        this.JiraReporter = httpRequest.Params["reporter"] ?? string.Empty;
        this.AttachmentIds = httpRequest.Params["attachments"] ?? string.Empty;
        this.MsmContactEmail = httpRequest.Params["contactEmail"] ?? string.Empty;
        this.IssueUrl = httpRequest.Params["issueUrl"] ?? string.Empty;
    }

    /// <summary>
    /// Route Request via Action
    /// </summary>
    private void RouteRequest(string action, HttpContext context)
    {
        HttpWebRequest httpWebRequest;
        this.GetJIRAFielInformation();
        switch (action)
        {
            case "PreRequisiteCheck":
                context.Response.Write(this.PreRequisiteCheck());
       
                break;
            case "GetJiraIssues":
               
                if (this.JIRAFieldType == "number") {
                   httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("search?jql='{0}'={1}", this.CustomFieldName, this.msmRequestNo), null, "GET", this.Proxy);
                } else {
                   httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("search?jql='{0}'~{1}", this.CustomFieldName, this.msmRequestNo), null, "GET", this.Proxy);
                }
                context.Response.Write(ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials));
                break;
            case "LinkJiraIssue":
                this.UpdateJiraIssue(this.msmRequestNo);
                httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("issue/{0}", this.JiraIssueNo), null, "GET", this.Proxy);
                context.Response.Write(ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials));
                break;
            case "UnlinkJiraIssue":
                
                
                context.Response.Write(this.UpdateJiraIssue(null));
                break;
            case "CreateJiraIssue":
               
                dynamic result = this.CreateJiraIssue();
                httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("issue/{0}", result.key), null, "GET", this.Proxy);
                context.Response.Write(ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials));
                break;
            case "MoveStatus":
                this.MoveMsmStatus(context.Request);
                break;
            case "GetProjectsIssueTypes":
                var results = this.GetJiraProjectIssueTypeMapping();
                context.Response.Write(JsonConvert.SerializeObject(results));
                break;
            case "GetJiraUsers":
                httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("user/search?query={0}", this.MsmContactEmail), null, "GET", this.Proxy);
                context.Response.Write(ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials));
                break;
            case "SendAttachments":
                if (!string.IsNullOrEmpty(this.AttachmentIds))
                {
                    var attachmentNumIds = Array.ConvertAll(this.AttachmentIds.Split(','), Convert.ToInt32);
                    var att = this.GetAttachmentDtOs(attachmentNumIds);
                    var attachmentResult = this.PostAttachments(att, this.JiraIssueNo);
                    context.Response.Write(attachmentResult);
                }
                break;
            case "ViewSummary":
                httpWebRequest = ApiHandler.BuildRequest(this.IssueUrl, null, "GET", this.Proxy);
                context.Response.Write(this.BuildPreview(context, ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials)));
                break;
        }
    }

    private string LoadSummaryTemplate(HttpContext context)
    {
        return File.ReadAllText(context.Server.MapPath(string.Format("{0}/MarvalSoftware.Plugins.Jira.Summary.html", this.PluginRelativeBaseUrl)));
    }

    /// <summary>
    /// Build a summary preview of the jira issue to display in MSM
    /// </summary>
    /// <returns></returns>
    private string BuildPreview(HttpContext context, string issueString)
    {
        if (string.IsNullOrEmpty(issueString)) return string.Empty;
        var issueDetails = this.PopulateIssueDetails(issueString);
        var processedTemplate = this.PreProcessTemplateResourceStrings(this.LoadSummaryTemplate(context));
        string razorTemplate;
        using (var razor = new RazorHelper())
        {
            bool isError;
            razorTemplate = razor.Render(processedTemplate, issueDetails, out isError);
        }
        return razorTemplate;
    }

    private Dictionary<string, string> PopulateIssueDetails(string issueString)
    {
        var issue = JsonHelper.FromJson(issueString);
        var issueDetails = new Dictionary<string, string>();

        var issueType = issue.fields["issuetype"];
        issueDetails.Add("issueTypeIconUrl", Convert.ToString(issueType.iconUrl));
        issueDetails.Add("issueTypeName", Convert.ToString(issueType.name));

        var project = issue.fields["project"];
        issueDetails.Add("projectIconUrl", Convert.ToString(project.avatarUrls["32x32"]));
        issueDetails.Add("issueUrl", this.BaseUrl + string.Format("browse/{0}", issue.key));
        issueDetails.Add("summary", HttpUtility.HtmlEncode(Convert.ToString(issue.fields["summary"])));
        issueDetails.Add("issueProjectAndKey", string.Format("{0} / {1}", project.name, issue.key));

        var status = issue.fields["status"];
        var statusCategory = status.statusCategory;
        issueDetails.Add("statusName", Convert.ToString(status.name));
        issueDetails.Add("statusCategoryBackgroundColor", Convert.ToString(statusCategory.colorName));

        var priority = issue.fields["priority"];
        issueDetails.Add("priorityName", Convert.ToString(priority.name));
        issueDetails.Add("priorityIconUrl", Convert.ToString(priority.iconUrl));

        var resolution = issue.fields["resolution"];
        issueDetails.Add("resolution", resolution != null ? Convert.ToString(resolution.name) : "Unresolved");

        var affectedVersions = (JArray)issue.fields["versions"];
        issueDetails.Add("affectsVersions", affectedVersions.Any() ? string.Join(",", affectedVersions.Select(av => ((dynamic)av).name)) : "None");

        var fixVersions = (JArray)issue.fields["fixVersions"];
        issueDetails.Add("fixVersions", fixVersions.Any() ? string.Join(",", fixVersions.Select(fv => ((dynamic)fv).name)) : "None");

        var components = (JArray)issue.fields["components"];
        issueDetails.Add("components", components.Any() ? string.Join(",", components.Select(c => ((dynamic)c).name)) : "None");

        var labels = (JArray)issue.fields["labels"];
        issueDetails.Add("labels", labels.Any() ? string.Join(",", labels.Select(c => ((dynamic)c).Value)) : "None");
        issueDetails.Add("storyPoints", Convert.ToString(issue.fields["customfield_10006"]));

        var assignee = issue.fields["assignee"];
        issueDetails.Add("assigneeName", assignee != null ? Convert.ToString(assignee.displayName) : "Unassigned");
        issueDetails.Add("assigneeIconUrl", assignee != null ? Convert.ToString(assignee.avatarUrls["16x16"]) : string.Empty);

        var reporter = issue.fields["reporter"];
        issueDetails.Add("reporterName", reporter != null ? Convert.ToString(reporter.displayName) : string.Empty);
        issueDetails.Add("reporterIconUrl", reporter != null ? Convert.ToString(reporter.avatarUrls["16x16"]) : string.Empty);

        DateTime createdDate;
        issueDetails.Add("created", string.Empty);
        if (DateTime.TryParse(Convert.ToString(issue.fields["created"]), out createdDate))
        {
            issueDetails["created"] = this.GetRelativeTime(createdDate);
        }

        DateTime updatedDate;
        issueDetails.Add("updated", string.Empty);
        if (DateTime.TryParse(Convert.ToString(issue.fields["updated"]), out updatedDate))
        {
            issueDetails["updated"] = this.GetRelativeTime(updatedDate);
        }

        issueDetails.Add("description", this.ProcessJiraDescription(issue));
        issueDetails.Add("msmLink", string.Empty);
        issueDetails.Add("msmLinkName", string.Empty);
        issueDetails.Add("requestTypeIconUrl", string.Empty);

        if (issue.fields[this.CustomFieldId] == null) return issueDetails;
        var requestId = Convert.ToString(issue.fields[this.CustomFieldId]);
        var msmResponse = string.Empty;

        try
        {
            msmResponse = ApiHandler.ProcessRequest(ApiHandler.BuildRequest(this.MSMBaseUrl + string.Format("/api/serviceDesk/operational/requests/{0}", requestId), null, "GET", this.Proxy), ApiHandler.GetEncodedCredentials(this.MsmApiKey));
            var requestResponse = JObject.Parse(msmResponse);
            issueDetails["msmLinkName"] = string.Format("{0}-{1} {2}", requestResponse["entity"]["data"]["type"]["acronym"], requestResponse["entity"]["data"]["number"], requestResponse["entity"]["data"]["description"]);
            issueDetails["msmLink"] = string.Format("{0}{1}/RFP/Forms/Request.aspx?id={2}", HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority), MarvalSoftware.UI.WebUI.ServiceDesk.WebHelper.ApplicationPath, requestId);
            issueDetails["requestTypeIconUrl"] = this.GetRequestBaseTypeIconUrl(Convert.ToInt32(requestResponse["entity"]["data"]["type"]["baseTypeId"]));
        }
        catch(Exception ex)
        {
            issueDetails["msmLinkName"] = null;
        }

        return issueDetails;
    }

    private string ProcessJiraDescription(dynamic issue)
    {
        var description = Convert.ToString(issue.fields["description"]);
        if (string.IsNullOrEmpty(description)) return description;

        description = Convert.ToString(this.InvokeCustomPluginStaticTypeMember("WikiNetParser.dll", "WikiNetParser.WikiProvider", "ConvertToHtml", new[] { description }));
        foreach (System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(description, @"!(.*)!"))
        {
            if (match.Groups.Count <= 1) continue;

            var filename = match.Groups[1].Value;
            var dimension = string.Empty;
            var dimensionMatch = System.Text.RegularExpressions.Regex.Match(filename, @"(.*)\|width=([0-9]*),height=([0-9]*)");
            if (dimensionMatch.Success && dimensionMatch.Groups.Count > 2)
            {
                filename = dimensionMatch.Groups[1].Value;
                dimension = string.Format(" width='{0}' height='{1}' ", dimensionMatch.Groups[2].Value, dimensionMatch.Groups[3].Value);
            }

            var attachment = (dynamic)((JArray)issue.fields["attachment"]).FirstOrDefault(att => string.Equals(Convert.ToString(((dynamic)att).filename), filename, StringComparison.OrdinalIgnoreCase));
            if (attachment != null)
            {
                description = description.Replace(match.Groups[0].Value, string.Format("<img src='{0}' title='{1}'{2}/>", Convert.ToString(attachment.content), filename, dimension));
            }
        }

        return description;
    }

    private string GetRequestBaseTypeIconUrl(int requestBaseType)
    {
        var baseRequestType = (MarvalSoftware.ServiceDesk.ServiceSupport.BaseRequestTypes)requestBaseType;
        string icon = baseRequestType.ToString().ToLower();
        if (icon == "changerequest")
        {
            icon = "change";
        }
        return string.Format("{0}{1}/Assets/Skins/{2}/Icons/{3}_32.png", HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority), MarvalSoftware.UI.WebUI.ServiceDesk.WebHelper.ApplicationPath, MarvalSoftware.UI.WebUI.Style.StyleSheetManager.Skin, icon);
    }

    private void GetJIRAFielInformation() {
        HttpWebRequest httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + "field", null, "GET", this.Proxy);
        var fieldsResponse = ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials);
       
        var responseFieldObj = JArray.Parse(fieldsResponse);
       foreach (dynamic field in responseFieldObj)
       {
          if (field.name == this.CustomFieldName) {
             this.JIRAFieldID = field.id;
             this.CustomFieldId = field.id;
             
             this.JIRAFieldType = field.schema.type;
          }
      }
    }

    /// <summary>
    /// Retrieves the issue types for each JIRA project.
    /// </summary>
    /// <returns>A sorted dictionary of projects and their issue types.</returns>
    public SortedDictionary<string, string[]> GetJiraProjectIssueTypeMapping()
    {
        HttpWebRequest httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + "project", null, "GET", this.Proxy);
        var response = ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials);
        JArray projects = JArray.Parse(response);

        var projectIssueTypes = new SortedDictionary<string, string[]>();
        var issueTypeTasks = new List<Task<string>>();

        foreach (JToken project in projects)
        {
            //Start the task
            var task = this.GetProjectIssueTypesAsync(project["key"].ToString());
            task.ConfigureAwait(false);
            issueTypeTasks.Add(task);
        }

        //Wait for all issue types before sorting
        Task.WaitAll(issueTypeTasks.ToArray());

        foreach (var task in issueTypeTasks) {
            var taskResult = JObject.Parse(task.Result);
            //Filter out subtasks and Epic types and select only the issuetype's name.
            var issueTypes = taskResult["issueTypes"].Where(type => type["subtask"].ToString().Equals("False") && !(type["name"].ToString().Equals("Epic"))).Select(type => type["name"].ToString()).ToArray();

            Array.Sort(issueTypes, string.CompareOrdinal);
            projectIssueTypes.Add(taskResult["key"].ToString(), issueTypes);
        }

        return projectIssueTypes;
    }

    /// <summary>
    /// Asyncrhonously retrieves the issue types for a given JIRA project key.
    /// </summary>
    /// <param name="projectKey"></param>
    /// <returns>A task which will eventually contain a JSON string.</returns>
    public async Task<string> GetProjectIssueTypesAsync(string projectKey)
    {
        HttpWebRequest request = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("project/{0}", projectKey), null, "GET", this.Proxy);
        request.Headers.Add("Authorization", "Basic " + this.JiraCredentials);

        using (WebResponse response = await request.GetResponseAsync().ConfigureAwait(false))
        {
            using (StreamReader reader = new StreamReader(response.GetResponseStream()))
            {
                return await reader.ReadToEndAsync();
            }
        }
    }

    /// <summary>
    /// Gets attachment DTOs from array of attachment Ids
    /// </summary>
    /// <param name="attachmentIds"></param>
    /// <returns>A list of attachment DTOs</returns>
    public List<AttachmentViewInfo> GetAttachmentDtOs(int[] attachmentIds) {
        var attachmentFacade = new RequestManagementFacade();
        return attachmentIds.Select(attachment => attachmentFacade.ViewAnAttachment(attachment)).ToList();
    }

    /// <summary>
    /// Link attachments to specified Jira issue.
    /// </summary>
    /// <param name="attachments"></param>
    /// <param name="issueKey"></param>
    /// <returns>The result of attempting to post the attachment data.</returns>
    public string PostAttachments(List<AttachmentViewInfo> attachments, string issueKey) {
        var boundary = string.Format("----------{0:N}", Guid.NewGuid());
        var content = new MemoryStream();
        var writer = new StreamWriter(content);
        var result = HttpStatusCode.OK.ToString();

        foreach (var attachment in attachments)
        {
            var data = attachment.Content;
            writer.WriteLine("--{0}", boundary);
            writer.WriteLine("Content-Disposition: form-data; name=\"file\"; filename=\"{0}\"", attachment.Name);
            writer.WriteLine("Content-Type: " + attachment.ContentType);
            writer.WriteLine();
            writer.Flush();
            content.Write(data, 0, data.Length);
            writer.WriteLine();
        }
        writer.WriteLine("--" + boundary + "--");
        writer.Flush();
        content.Seek(0, SeekOrigin.Begin);

        HttpWebResponse response;
        HttpWebRequest request = WebRequest.Create(new UriBuilder(this.ApiBaseUrl + "issue/" + issueKey + "/attachments").Uri) as HttpWebRequest;
        request.Method = "POST";
        request.ContentType = string.Format("multipart/form-data; boundary={0}", boundary);
        request.Headers.Add("Authorization", "Basic " + this.JiraCredentials);
        request.Headers.Add("X-Atlassian-Token", "nocheck");
        request.KeepAlive = true;
        request.ContentLength = content.Length;

        using (Stream requestStream = request.GetRequestStream())
        {
            content.CopyTo(requestStream);
        }

        using (response = request.GetResponse() as HttpWebResponse)
        {
            if (response.StatusCode != HttpStatusCode.OK)
            {
                result = response.StatusCode.ToString();
            }
        }
        return result;
    }

    /// <summary>
    /// Create New Jira Issue
    /// </summary>
    private JObject CreateJiraIssue()
    {
        dynamic jobject = JObject.FromObject(new
        {
            fields = new
            {
                project = new
                {
                    key = this.JiraProject
                },
                summary = this.JiraSummary,
                issuetype = new
                {
                    name = this.JiraType
                }
            }
        });

       
        if (JIRAFieldType == "number") {
           jobject.fields[this.CustomFieldId] = this.msmRequestNo;
        } else {
           jobject.fields[this.CustomFieldId] = "\"" + this.msmRequestNo + "\"";
        }
        

        if (!this.JiraReporter.Equals("null")) {
            dynamic reporter = new JObject();
            reporter.name = this.JiraReporter;
            jobject.fields["reporter"] = reporter;
        }

        var httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + "issue/", jobject.ToString(), "POST", this.Proxy);
        return JObject.Parse(ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials));
    }

    /// <summary>
    /// Update Jira Issue
    /// </summary>
    /// <param name="value">Value to update custom field in JIRA with</param>
    /// <returns>Process Response</returns>
    private string UpdateJiraIssue(int? value)
    {
        IDictionary<string, object> body = new Dictionary<string, object>();
        IDictionary<string, object> result = new Dictionary<string, object>();
       
       
        result.Add(this.CustomFieldId, value);
        body.Add("fields", result);
        var httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("issue/{0}", this.JiraIssueNo), JsonHelper.ToJson(body), "PUT", this.Proxy);
        return ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials);
    }

static object[] ProcessArray(Array array)
{
    // Process each element of the array, you might need to convert them based on their types
    List<object> processedArray = new List<object>();
    foreach (var item in array)
    {
        if (item is string || item is int || item is double || item is bool)
        {
            processedArray.Add(item);
        }
        else
        {
        try {
            // Handle other types or convert them to string
            processedArray.Add(item.ToString());
            }
            catch (Exception ex) {

            }
        }
    }
    return processedArray.ToArray();
}

static Dictionary<string, object> GetFormFields(dynamic form)
{
    Dictionary<string, object> fields = new Dictionary<string, object>();

    foreach (dynamic fieldset in form.fieldsets)
    {
        foreach (dynamic field in fieldset.fields)
        {
            string fieldName = field.name;
            object fieldValue = field.value;

            // Handle different types and convert them to object
    try {
            if (fieldValue is string || fieldValue is int || fieldValue is double || fieldValue is bool)
            {
                fields[fieldName] = fieldValue;
            }
            else if (fieldValue.ToString().StartsWith("[") && fieldValue.ToString().EndsWith("]"))
                {
                  
                     string[] elements = fieldValue.ToString().Trim('[', ']').Split(',');
                     List<object> arrayValues = new List<object>();
                     foreach (var element in elements)
    {
             int result = Int32.Parse(element);
            arrayValues.Add(result);
        }
                    
                   fields[fieldName] = arrayValues.ToArray();
                }
            else
            {
                 try
            {
                fields[fieldName] = fieldValue.ToString();
                 }
                 catch (Exception ex) {
                 Log.Information("Error assigning field value to field name " + ex);
                 }
              }
              } catch (Exception ex) {
              Log.Information("Error building array " + ex);
              }
            
        }
    }

    return fields;
}
public static dynamic GetForm(string formName, dynamic response)
    {
       foreach (var form in response.forms)
       {
            if (form.name == formName)
            {
                return form;
            }
       }
       return null;
    }

    /// <summary>
    /// Move MSM Status
    /// </summary>
    /// <param name="httpRequest">The HttpRequest</param>
    /// <returns>Process Response</returns>
    private void MoveMsmStatus(HttpRequest httpRequest)
    {
        int requestNumber;

        var isValid = this.StatusValidation(httpRequest, out requestNumber);

        var httpWebRequest = ApiHandler.BuildRequest(this.MSMBaseUrl + string.Format("/api/serviceDesk/operational/requests?number={0}", requestNumber), null, "GET", this.Proxy);
        
        var requestNumberResponse = JObject.Parse(ApiHandler.ProcessRequest(httpWebRequest, ApiHandler.GetEncodedCredentials(this.MsmApiKey)));
        var requestId = (int)requestNumberResponse["collection"]["items"].First["entity"]["data"]["id"];

        httpWebRequest = ApiHandler.BuildRequest(this.MSMBaseUrl + string.Format("/api/serviceDesk/operational/requests/{0}", requestId), null, "GET", this.Proxy);
        var requestIdResponse = JObject.Parse(ApiHandler.ProcessRequest(httpWebRequest, ApiHandler.GetEncodedCredentials(this.MsmApiKey)));
        var workflowId = requestIdResponse["entity"]["data"]["requestStatus"]["workflowStatus"]["workflow"]["id"];

        var formDetail = GetForm("moveStatus",requestIdResponse);
        Dictionary<string, object> jsonBody = GetFormFields(formDetail);
 
        if (isValid)
        {
            // Get the next workflow states for the request...
            httpWebRequest = ApiHandler.BuildRequest(this.MSMBaseUrl + string.Format("/api/serviceDesk/operational/workflows/{0}/nextStates?requestId={1}&namePredicate=equals({2})", workflowId, requestId, httpRequest.QueryString["status"]), null, "GET", this.Proxy);
            var requestWorkflowResponse = JObject.Parse(ApiHandler.ProcessRequest(httpWebRequest, ApiHandler.GetEncodedCredentials(this.MsmApiKey)));
            var workflowResponseItems = (IList<JToken>)requestWorkflowResponse["collection"]["items"];

            if (workflowResponseItems.Count > 0)
            {
                // Attempt to move the request state.
               
                dynamic msmPutRequest = new ExpandoObject();
                msmPutRequest.WorkflowStatusId = workflowResponseItems[0]["entity"]["data"]["id"];
                msmPutRequest.UpdatedOn = (DateTime)requestNumberResponse["collection"]["items"].First["entity"]["data"]["updatedOn"];
                var WorkflowStatusId = workflowResponseItems[0]["entity"]["data"]["id"].ToString();
                var UpdatedOn = requestNumberResponse["collection"]["items"].First["entity"]["data"]["updatedOn"].ToString();
                jsonBody["WorkflowStatusId"] = WorkflowStatusId;
                jsonBody["UpdatedOn"] = (DateTime)requestNumberResponse["collection"]["items"].First["entity"]["data"]["updatedOn"];
                httpWebRequest = ApiHandler.BuildRequest(this.MSMBaseUrl + string.Format("/api/serviceDesk/operational/requests/{0}/states", requestId), JsonHelper.ToJson(jsonBody), "POST", this.Proxy);
                
                var moveStatusResponse = ApiHandler.ProcessRequest(httpWebRequest, ApiHandler.GetEncodedCredentials(this.MsmApiKey));
                
            
                if (moveStatusResponse.Contains("500"))
                {
                    this.AddMsmNote(requestId, "JIRA status update failed: a server error occured.");
                }
            }
            else
            {
                this.AddMsmNote(requestId, "JIRA status update failed: " + httpRequest.QueryString["status"] + " is not a valid next state.");
            }
        }
        else
        {
            this.AddMsmNote(requestId, "JIRA status update failed: all linked JIRA issues must be in the same status.");
        }
    }

    /// <summary>
    /// Add MSM Note
    /// </summary>   
    private void AddMsmNote(int requestNumber, string note)
    {
        IDictionary<string, object> body = new Dictionary<string, object>();
        body.Add("id", requestNumber);
        body.Add("content", note);
        body.Add("type", "public");

        var httpWebRequest = ApiHandler.BuildRequest(this.MSMBaseUrl + string.Format("/api/serviceDesk/operational/requests/{0}/notes/", requestNumber), JsonHelper.ToJson(body), "POST", this.Proxy);
        ApiHandler.ProcessRequest(httpWebRequest, ApiHandler.GetEncodedCredentials(this.MsmApiKey));
    }

    /// <summary>
    /// Validate before moving MSM status
    /// </summary>
    /// <param name="httpRequest">The HttpRequest</param>
    /// <param name="requestNumber">Out the request number</param>
    /// <returns>Boolean to determine if Valid</returns>
    private bool StatusValidation(HttpRequest httpRequest, out int requestNumber)
    {

        var json = new StreamReader(httpRequest.InputStream).ReadToEnd();
       
        dynamic data = JObject.Parse(json);
       
        var MarvalRequestNum = data.issue.fields[this.CustomFieldId].Value;
        try {
           MarvalRequestNum = MarvalRequestNum.Replace("\"", "");
        }
        catch (Exception ex) {

        }
        
        bool isString = false;
        try {
        isString = int.TryParse(MarvalRequestNum, out requestNumber);
         }
         catch (Exception ex) {
                requestNumber = (int)data.issue.fields[this.CustomFieldId].Value;
         }
        if (isString) {
           
           } else {
           // requestNumber = (int)data.issue.fields[this.CustomFieldId].Value;
           // requestNumber = MarvalRequestNum;

           }
        
        
        if (requestNumber <= 0 || httpRequest.QueryString["status"] == null) return false;
       
      
        HttpWebRequest httpWebRequest;
        if (this.JIRAFieldType == "number") {
       
           httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("search?jql='{0}'={1}", this.CustomFieldName, requestNumber), null, "GET", this.Proxy);
        } else {
      
           httpWebRequest = ApiHandler.BuildRequest(this.ApiBaseUrl + string.Format("search?jql='{0}'~{1}", this.CustomFieldName, requestNumber), null, "GET", this.Proxy);
        }
       
        dynamic d = JObject.Parse(ApiHandler.ProcessRequest(httpWebRequest, this.JiraCredentials));
        
        var isValidStatus = false;
        foreach (var issue in d.issues)
        {
            if (issue.fields.status.name.Value == data.transition.to_status.Value)
            {
            isValidStatus = true;
            }
        }
        if (isValidStatus) {
           return true;
        } else {
           return false;
        }
    }

    /// <summary>
    /// Check and return missing plugin settings
    /// </summary>
    /// <returns>Json Object containing any settings that failed the check</returns>
    private JObject PreRequisiteCheck()
    {
        var preReqs = new JObject();
        if (string.IsNullOrWhiteSpace(this.CustomFieldName))
        {
            Log.Information("Have a validation error on custom field name");
            preReqs.Add("jiraCustomFieldName", false);
        }
        if (string.IsNullOrWhiteSpace(this.ApiBaseUrl))
        {
        Log.Information("Have a validation error on ApiBaseUrl");
            preReqs.Add("jiraBaseUrl", false);
        }
        if (string.IsNullOrWhiteSpace(this.Username))
        {
        Log.Information("Have a validation error on Username");
            preReqs.Add("jiraUsername", false);
        }
        if (string.IsNullOrWhiteSpace(this.Password))
        {
        Log.Information("Have a validation error on Password");
            preReqs.Add("jiraPassword", false);
        }

        return preReqs;
    }

    //Generic Methods

    /// <summary>
    /// Builds a HttpWebRequest
    /// </summary>
    /// <param name="uri">The uri for request</param>
    /// <param name="body">The body for the request</param>
    /// <param name="method">The verb for the request</param>
    /// <returns>The HttpWebRequest ready to be processed</returns>
    private static HttpWebRequest BuildRequest(string uri = null, string body = null, string method = "GET", IWebProxy proxy = null)
    {
        var request = WebRequest.Create(new UriBuilder(uri).Uri) as HttpWebRequest;
        request.Proxy = proxy;
        request.Method = method.ToUpperInvariant();
        request.ContentType = "application/json";
        if (body == null) return request;
        using (var writer = new StreamWriter(request.GetRequestStream()))
        {
            writer.Write(body);
        }

        return request;
    }

    /// <summary>
    /// Proccess a HttpWebRequest
    /// </summary>
    /// <param name="request">The HttpWebRequest</param>
    /// <param name="credentials">The Credentails to use for the API</param>
    /// <returns>Process Response</returns>
    private static string ProcessRequest(HttpWebRequest request, string credentials)
    {
        try
        {
            request.Headers.Add("Authorization", "Basic " + credentials);
            HttpWebResponse response = request.GetResponse() as HttpWebResponse;
            using (StreamReader reader = new StreamReader(response.GetResponseStream()))
            {
                return reader.ReadToEnd();
            }
        }
        catch (WebException ex)
        {
            return ex.Message;
        }

    }

    /// <summary>
    /// Encodes Credentials
    /// </summary>
    /// <param name="credentials">The string to encode</param>
    /// <returns>base64 encoded string</returns>
    private static string GetEncodedCredentials(string credentials)
    {
        var byteCredentials = Encoding.UTF8.GetBytes(credentials);
        return Convert.ToBase64String(byteCredentials);
    }

    /// <summary>
    /// JsonHelper Functions
    /// </summary>
    internal class JsonHelper
    {
        public static string ToJson(object obj)
        {
            return JsonConvert.SerializeObject(obj);
        }

        public static dynamic FromJson(string json)
        {
            return JObject.Parse(json);
        }
    }

    private string GetRelativeTime(DateTime date)
    {
        var ts = new TimeSpan(DateTime.Now.Ticks - date.Ticks);
        var delta = Math.Abs(ts.TotalSeconds);
        var localTimeOfDay = date.ToShortTimeString();

        if (delta < 1 * ApiHandler.minute)
        {
            return ts.Seconds == 1 ? this.GetResourceString("@@OneSecondAgo") : this.GetResourceString("@@AFewSecondsAgo");
        }

        if (delta < 2 * ApiHandler.minute)
        {
            return this.GetResourceString("@@OneMinuteAgo");
        }

        if (delta < 60 * ApiHandler.minute)
        {
            return this.GetResourceString("@@MinutesAgo", Math.Floor(ts.TotalMinutes));
        }

        if (delta < 61 * ApiHandler.minute)
        {
            return this.GetResourceString("@@OneHourAgo");
        }

        if (delta < 24 * ApiHandler.hour)
        {
            return this.GetResourceString("@@HoursAgo", Math.Floor(ts.TotalHours));
        }

        if (delta < 48 * ApiHandler.hour)
        {
            return this.GetResourceString("@@YesterdayAt", localTimeOfDay);
        }
        
        if (delta < 7 * ApiHandler.day)
        {
            return this.GetResourceString("@@DaysAgo", Math.Floor(ts.TotalDays));
        }

        return date.ToString("dd/MMM/yy hh:mm tt");
    }
}
