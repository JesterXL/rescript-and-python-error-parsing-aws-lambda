open Promise
open Jzon
open Environment

type parseBase64Result = {
    ok: bool,
    result: Js.Nullable.t<Js.Json.t>,
    reason: Js.Nullable.t<string>
}

@module("./buffer.js") external parseBase64: string => parseBase64Result = "parseBase64"

type unzipResult = {
    ok: bool,
    result: Js.Nullable.t<string>,
    reason: Js.Nullable.t<string>
}

@module("./buffer.js") external unzip: Js.Json.t => unzipResult = "unzip"

type awsData = {
    data: string
}
type cloudWatchLogEvent = {
    awslogs: awsData
}

let parseAWSEventBody = event => {
    let result = parseBase64(event.awslogs.data)
    if(result.ok === true) {
       switch Js.Nullable.toOption(result.result) {
       | None => Error("Parsing the AWS Event body was successful, but the JavaScript returned no result.")
       | Some(result_) => Ok(result_)
       }
    } else {
        switch Js.Nullable.toOption(result.reason) {
        | None => Error("Parsing the AWS Event body failed, but JavaScript didn't tell us why.")
        | Some(reason_) => Error(reason_)
        }
    }
}

let unzipData = data => {
    let result = unzip(data)
    if(result.ok === true) {
        switch Js.Nullable.toOption(result.result) {
        | None => Error("Successfully unzipped the AWS event data, but the JavaScript returned no result.")
        | Some(result_) => Ok(result_)
        }
    } else {
        switch Js.Nullable.toOption(result.reason) {
        | None => Error("Unzipping the AWS event body failed, but JavaScript didn't tell us why.")
        | Some(reason_) => Error(reason_)
        }
    }
}


type logEvent = {
    id:string,
    timestamp:float,
    message:string
}

type cloudWatchLogMessage = {
    messageType:string,
    owner:string,
    logGroup:string,
    logStream:string,
    subscriptionFilters:Js.Array.t<string>,
    logEvents:Js.Array.t<logEvent>
}

type errorEvent = {
    errorType:string,
    errorMessage:string,
    stack:Js.Array.t<string>
}

type snsErrorMessage = {
    lambdaName:string,
    logGroup:string,
    logStream:string,
    messages: Js.Array.t<errorEvent>
}

module Codecs = {
    let awsData = Jzon.object1(
        ({data}) => (data),
        ((data)) => { data: data } -> Ok,

        Jzon.field("data", Jzon.string)
    )
    let cloudWatchLogEvent = Jzon.object1(
        ({awslogs}) => (awslogs),
        ((awslogs)) => { awslogs: awslogs } -> Ok,

        Jzon.field("awslogs", awsData)
    )

    let logEvent = Jzon.object3(
        ({id, timestamp, message}) => (id, timestamp, message),
        ((id, timestamp, message)) => { id:id, timestamp:timestamp, message:message} -> Ok,
        Jzon.field("id", Jzon.string),
        Jzon.field("timestamp", Jzon.float),
        Jzon.field("message", Jzon.string)
    )

    let cloudWatchLogMessage = Jzon.object6(
        ({messageType, owner, logGroup, logStream, subscriptionFilters, logEvents}) => (messageType, owner, logGroup, logStream, subscriptionFilters, logEvents),
        ((messageType, owner, logGroup, logStream, subscriptionFilters, logEvents)) => { messageType, owner, logGroup, logStream, subscriptionFilters, logEvents} -> Ok,
        Jzon.field("messageType", Jzon.string),
        Jzon.field("owner", Jzon.string),
        Jzon.field("logGroup", Jzon.string),
        Jzon.field("logStream", Jzon.string),
        Jzon.field("subscriptionFilters", Jzon.array(Jzon.string)),
        Jzon.field("logEvents", Jzon.array(logEvent))
    )

    let errorEvent = Jzon.object3(
        ({errorType, errorMessage, stack}) => (errorType, errorMessage, stack),
        ((errorType, errorMessage, stack)) => { errorType, errorMessage, stack} -> Ok,
        Jzon.field("errorType", Jzon.string),
        Jzon.field("errorMessage", Jzon.string),
        Jzon.field("stack", Jzon.array(Jzon.string))
    )

    let snsErrorMessage = Jzon.object4(
        ({lambdaName, logGroup, logStream, messages}) => (lambdaName, logGroup, logStream, messages),
        ((lambdaName, logGroup, logStream, messages)) => { lambdaName, logGroup, logStream, messages} -> Ok,
        Jzon.field("lambdaName", Jzon.string),
        Jzon.field("logGroup", Jzon.string),
        Jzon.field("logStream", Jzon.string),
        Jzon.field("messages", Jzon.array(errorEvent))
    )
}

let parseAWSEvent = event => {
    Js.log2("parseAWSEvent, event:", event)
    switch Jzon.decodeWith(event, Codecs.cloudWatchLogEvent) {
    | Error(reason) => Error("parseAWSEvent failed to decode the AWS CloudWatch event: " ++ DecodingError.toString(reason))
    | Ok(data) => Ok(data)
    }
}


let basicJSONParse = string => {
    Js.log2("basicJSONParse, string:",string)
    switch Jzon.decodeString(Codecs.cloudWatchLogMessage, string) {
    | Error(reason) => {
        Js.log2("basicJSONParse failed:", DecodingError.toString(reason))
        Error(DecodingError.toString(reason))
    }
    | Ok(data) => {
        Js.log2("basicJSONParse succeeded:", data)
        Ok(data)
    }
    }
}

let attemptToMakeMessageValidJSON = logMessageText =>
    Js.String.substring(~from=Js.String.indexOf("{", logMessageText), ~to_=Js.String.length(logMessageText), logMessageText)

let cleanUpLogEventMessages = cloudWatchLog => {
    let cleanedLogEvents = Js.Array.map(
        logEvent =>
            {...logEvent, message: attemptToMakeMessageValidJSON(logEvent.message)},
        cloudWatchLog.logEvents
    )
    {...cloudWatchLog, logEvents: cleanedLogEvents} -> Ok
}


let formatMessageForSNS = (cloudWatchLog:cloudWatchLogMessage) => {
    let errorMessagesResults = 
        Js.Array.map(
            logMessage =>
                logMessage.message,
            cloudWatchLog.logEvents
        )
        -> Js.Array.map(
            message => {
                let result = Jzon.decodeString(Codecs.errorEvent, message)
                switch result {
                | Error(reason) => Js.log2("wat:", DecodingError.toString(reason))
                | Ok(_) => Js.log("nope")
                }
                result
            },
            _
        )
    
    if(Js.Array.some(Belt.Result.isError, errorMessagesResults) === true) {
        switch Js.Array.filter(Belt.Result.isError, errorMessagesResults)->Belt.Array.get(0) {
        | None => Js.log("ok wat")
        | Some(yup) => Js.log2("failed:", yup)
        }
        Error(`Failed parsing 1 or more of the error messages.`)
    } else {
        let errorMessages =
            Js.Array.filter(Belt.Result.isOk, errorMessagesResults)
            -> Js.Array.map(
                ok =>
                    Belt.Result.getExn(ok),
                _
            )
        Js.log2("formatMessageForSNS, cloudWatchLog:", cloudWatchLog)
        let lambdaName = Js.String.split("/", cloudWatchLog.logGroup)->Belt.Array.get(3)->Belt.Option.getWithDefault("Unknwwn Lambda Name")
        let snsMessageWereSending = {
            lambdaName,
            logGroup: cloudWatchLog.logGroup,
            logStream: cloudWatchLog.logStream,
            messages: errorMessages
        }
        Js.log2("snsMessageWereSending about to send to SNS:", snsMessageWereSending)
        (
            (`Lambda Error for ${lambdaName}`, 
            Jzon.encodeString(Codecs.snsErrorMessage, snsMessageWereSending)
            )
        )->Ok
    }
}

type snsResult = {
    ok:bool,
    result:Js.Nullable.t<string>,
    reason:Js.Nullable.t<string>,
    error:Js.Nullable.t<string>
}
@module("./sns.js") external publish: (string, string, string) => Js.Promise.t<snsResult> = "publish"

let publishSNS = (publishFunc, arn, subject, message) => {
    Js.log4("publishSNS, arn:", arn, "message:", message)
    publishFunc(arn, subject, message)
    ->then(
        resultFromSNS => {
            Js.log2("publishSNS, resultFromSNS:", resultFromSNS)
            if(resultFromSNS.ok === true) {
                Js.log2("publishSNS succeeded, messageID:", resultFromSNS.result)
                resultFromSNS.result
                ->Js.Nullable.toOption
                ->Belt.Option.getWithDefault("unknown message ID")
                ->Ok
                ->resolve
            } else {
                let reason_ = resultFromSNS.reason -> Js.Nullable.toOption -> Belt.Option.getWithDefault("unknown reason")
                let error_ = resultFromSNS.error -> Js.Nullable.toOption -> Belt.Option.getWithDefault("unknown error")
                Js.log4("publishSNS failed, reason:", reason_, "error:", error_)
                resolve(Error(reason_))
            }
        }
    )
    ->catch(
        error => {
            Js.log2("publishSNS failed:", error)
            resolve(Error(`publishSNS failed, unknown reason.`))
        }
    )
}


let getArnFromEnvironment = () =>
    switch getEnvironment() {
    | QA => "arn:aws:sns:us-east-1:123123123123:app-dev-alerts-alarm"
    | Staging => "arn:aws:sns:us-east-1:123123123123:app-stage-alerts-alarm"
    | Production => "arn:aws:sns:us-east-1:123123123123:app-prod-alerts-alarm"
    }

exception SendErrorToSNSError(string)

let sendErrorToSNS = (snsPublish, event) => {
    Js.log2("event:", event)
    let result = parseAWSEvent(event)
    ->Belt.Result.flatMap(parseAWSEventBody)
    ->Belt.Result.flatMap(unzipData)
    ->Belt.Result.flatMap(basicJSONParse)
    ->Belt.Result.flatMap(cleanUpLogEventMessages)
    ->Belt.Result.flatMap(formatMessageForSNS)
    Js.log2("Result chain result:", result)

    switch result {
    | Error(reason) => {
        Js.log2("sendErrorToSNS failed:", reason)
        reject(SendErrorToSNSError(reason))
    }
    | Ok((subject, message)) => {
        Js.log4("got a message result text, now calling snsPublish, subject:", subject, "message:", message)
        snsPublish(getArnFromEnvironment(), subject, message)
        ->then(
            result => {
                Js.log2("snsPublish result:", result)
                switch result {
                | Error(reason) => {
                    Js.log2("sendErrorToSNS failed:", reason)
                    reject(SendErrorToSNSError(reason))
                }
                | Ok(messageID) => {
                    Js.log2("sendErrorToSNS succeeded, messageID:", messageID)
                    resolve(messageID)
                }
                }
            }
        )
    }
    }
}

let handler = event =>
    sendErrorToSNS(publishSNS(publish), event)