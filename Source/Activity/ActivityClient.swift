// Copyright 2016-2017 Cisco Systems Inc
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit
import ObjectMapper
import SparkSDKEncryptionKit
import Alamofire
import SwiftyJSON


public class ActivityClient {
    
    /// Callback when receive Message.
    ///
    /// - since: 1.4.0
    public var onMessageActivity:((MessageActivity) -> Void)?
    
    /// Callback when receive acknowledge activity.
    ///
    /// - since: 1.4.0
    public var onTypingActivity:((TypingActivity) -> Void)?
    
    /// Callback when delete Message.
    ///
    /// - since: 1.4.0
    public var onFlagActivity:((FlagActivity) -> Void)?
    
    
    let authenticator: Authenticator
    
    private func requestBuilder() -> ServiceRequest.ActivityServerBuilder {
        return ServiceRequest.ActivityServerBuilder(authenticator).path("activities")
    }
    
    private func statusRequestBuilder() ->ServiceRequest.ActivityServerBuilder {
        return ServiceRequest.ActivityServerBuilder(authenticator).path("status")
    }
    
    private func flagRequestBuilder() ->ServiceRequest.RainDropServerBuilder {
        return ServiceRequest.RainDropServerBuilder(authenticator).path("flags")
    }
    
    private func kmsRequestBuilder() -> ServiceRequest.KmsServerBuilder {
        return ServiceRequest.KmsServerBuilder(authenticator)
    }
    
    private func userInfoRequestBuilder() -> ServiceRequest.ActivityServerBuilder {
        return ServiceRequest.ActivityServerBuilder(authenticator)
    }
    
    /// Lists all messages in a room by room Id.
    /// If present, it includes the associated media content attachment for each message.
    /// The list sorts the messages in descending order by creation date.
    ///
    /// - parameter conversationId: The identifier of the conversation.
    /// - parameter sinceDate: the activities published date is after this date, format in "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    /// - parameter midDate: The activities published date is before or after this date. At most limit/2 activities activities before and limit/2 activities after the date will be included, format in "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    /// - parameter maxDate: the activities published date is before this date, format in "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    /// - parameter limit:  Maximum number of activities return. Default is 6.
    /// - parameter personRefresh: (experimental)control if the person detail in activity need to be refreshed to latest. If person detail got      refreshed, person.id will be in UUID format even if original one is email. Default is false.
    /// - parameter lastActivityFirst: Sort order for the activities. Default is true.
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func listMessageActivities(conversationId: String,
                                      sinceDate: String? = nil,
                                      maxDate: String? = nil,
                                      midDate: String? = nil,
                                      limit: Int? = nil,
                                      personRefresh: Bool? = false,
                                      lastActivityFirst: Bool? = false,
                                      queue: DispatchQueue? = nil,
                                      completionHandler: @escaping (ServiceResponse<[MessageActivity]>) -> Void)
    {
        let query = RequestParameter([
            "conversationId": conversationId,
            "sinceDate": sinceDate,
            "maxDate": maxDate,
            "maxDate": maxDate,
            "midDate": midDate,
            "limit": limit,
            "personRefresh": personRefresh,
            "lastActivityFirst": lastActivityFirst,
            ])
        
        let request = requestBuilder()
            .method(.get)
            .query(query)
            .queue(queue)
            .build()
        
        request.responseArray(completionHandler)
    }
    
    /// Detail of one messate activity.
    ///
    /// - parameter activityID: The identifier of the activity.
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func messageActivityDetail(activityID: String,
                                      queue: DispatchQueue? = nil,
                                      completionHandler: @escaping (ServiceResponse<MessageActivity>) -> Void)
    {
        let request = requestBuilder()
            .method(.get)
            .path(activityID)
            .queue(queue)
            .build()
        request.responseObject(completionHandler)
    }
    
    /// Posts a plain text message, to a conversation by conversation Id.
    ///
    /// - parameter conversation: The identifier of the conversation where the message is to be posted.
    /// - parameter content: The plain text message to be posted to the room.
    /// - parameter medtions: The mention items to be posted to the room.
    /// - parameter files: local file pathes to be uploaded to the room.
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func postMessage(conversationID: String,
                            content: String,
                            mentions: [ActivityMentionModel]? = nil,
                            files: [String]? = nil,
                            queue: DispatchQueue? = nil,
                            completionHandler: @escaping (ServiceResponse<MessageActivity>) -> Void)
    {
        
        let messageActivity = MessageActivity()
        messageActivity.conversationId = conversationID
        messageActivity.plainText = content
        messageActivity.action = MessageAction.post
        if let mentionItems = mentions{
            messageActivity.mentionItems = mentionItems
        }
        
        if let encrptionUrl = self.roomResources.filter({$0.conversationID == conversationID}).first?.encryptionUrl,
            let keyMetarial = self.roomResources.filter({$0.conversationID == conversationID}).first?.keyMaterial{
            messageActivity.encryptionKeyUrl = encrptionUrl
            let msgPostOperation = ActivityPostOperation(authenticator:self.authenticator,messageActivity: messageActivity, keyMaterial:  keyMetarial ,queue:queue, completionHandler: completionHandler)
            self.postingOperationQueue.addOperation(msgPostOperation)
        }else{
            if self.roomResources.filter({$0.conversationID == conversationID}).first == nil{
                let roomModel = ActivityRoomResource(conversationId: conversationID)
                self.roomResources.append(roomModel)
            }
            let msgPostOperation = ActivityPostOperation(authenticator:self.authenticator,messageActivity: messageActivity ,queue:queue, completionHandler: completionHandler)
            self.pendingOperationQueue.append(msgPostOperation)
            self.postNewMessageActivity(messageActivity: messageActivity)
        }
    }
    
    /// Deletes a message, to a conversation by conversation Id.
    ///
    /// - parameter conversation: The identifier of the conversation where the message is to be posted.
    /// - parameter activityId: The messageId to be deleted in the room.
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func deleteMessage(conversationID: String,
                              messageActivityId: String,
                              queue: DispatchQueue? = nil,
                              completionHandler: @escaping (ServiceResponse<MessageActivity>) -> Void)
    {
        
        let messageActivity = MessageActivity()
        messageActivity.conversationId = conversationID
        messageActivity.activityId = messageActivityId
        messageActivity.action = MessageAction.delete
        let msgPostOperation = ActivityPostOperation(authenticator:self.authenticator, messageActivity: messageActivity,queue:queue, completionHandler: completionHandler)
        self.postingOperationQueue.addOperation(msgPostOperation)
    }
    
    /// Post a message read indicator, to a conversation by conversation Id.
    ///
    /// - parameter conversation: The identifier of the conversation where the indicator is to be posted.
    /// - parameter activityId: The activity that is read .
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func read(conversationID: String,
                     massageActivityId: String,
                     queue: DispatchQueue? = nil,
                     completionHandler: @escaping (ServiceResponse<MessageActivity>) -> Void)
    {
        let messageActivity = MessageActivity()
        messageActivity.conversationId = conversationID
        messageActivity.activityId = massageActivityId
        messageActivity.action = MessageAction.acknowledge
        let msgPostOperation = ActivityPostOperation(authenticator:self.authenticator, messageActivity: messageActivity,queue:queue, completionHandler: completionHandler)
        self.postingOperationQueue.addOperation(msgPostOperation)
    }
    
    /// Post a typing indicator, to a conversation by conversation Id.
    ///
    /// - parameter conversation: The identifier of the conversation where the indicator is to be posted.
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func startTyping(conversationID: String,
                            queue: DispatchQueue? = nil,
                            completionHandler: @escaping (ServiceResponse<Any>) -> Void) -> Void
    {
        let body = RequestParameter([
            "eventType": "status.start_typing",
            "conversationId" : conversationID
            ])
        let request = statusRequestBuilder().path("typing")
            .method(.post)
            .body(body)
            .queue(queue)
            .build()
        request.responseJSON(completionHandler)
    }
    
    /// Post a stop-typing indicator, to a conversation by conversation Id.
    ///
    /// - parameter conversation: The identifier of the conversation where the indicator is to be posted.
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func stopTyping(conversationID: String,
                           queue: DispatchQueue? = nil,
                           completionHandler: @escaping (ServiceResponse<Any>) -> Void) -> Void
    {
        let body = RequestParameter([
            "eventType": "status.stop_typing",
            "conversationId" : conversationID
            ])
        let request = statusRequestBuilder().path("typing")
            .method(.post)
            .body(body)
            .queue(queue)
            .build()
        request.responseJSON(completionHandler)
    }
    
    /// Post flag an activity action, to a activity by activity url.
    ///
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func flag(flagItemUrl: String,
                     queue: DispatchQueue? = nil,
                     completionHandler: @escaping (ServiceResponse<FlagActivity>) -> Void) -> Void
    {
        let body = RequestParameter([
            "flag-item": flagItemUrl,
            "state": "flagged"
            ])
        
        let request = flagRequestBuilder()
            .method(.post)
            .body(body)
            .queue(queue)
            .build()
        request.responseObject(completionHandler)
    }
    
    /// Post  unflag an activity action, to a flag tem by flagId.
    ///
    /// - parameter queue: If not nil, the queue on which the completion handler is dispatched. Otherwise, the handler is dispatched on the application's main thread.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    /// - returns: Void
    /// - since: 1.4.0
    public func unFlag(flagItemId: String,
                       queue: DispatchQueue? = nil,
                       completionHandler: @escaping (ServiceResponse<Any>) -> Void) -> Void
    {
        let request = flagRequestBuilder().path(flagItemId)
            .method(.delete)
            .queue(queue)
            .build()
        request.responseJSON(completionHandler)
    }
    
    
    // MARK: Encryption Feature Variables
    private let successStr:String = "SUCCESS:"
    private let kmsMessageServerUri = ServiceRequest.KMS_SERVER_ADDRESS + "/kms/messages"
    private var kmsCluster: String?
    private var rsaPublicKey: String?
    private var ephemeralKeyRequest: KmsEphemeralKeyRequest?
    private var ephemeralKeyFetched: Bool = false
    private var ephemeralKeyStr: String = ""
    private var receivedActivityQueue : [MessageActivity] = [MessageActivity]()
    private var kmsRequestQueue : [KmsRequest] = [KmsRequest]()
    private var roomResources : [ActivityRoomResource] = [ActivityRoomResource]()
    private var postCompeletionHandler : ((ServiceResponse<MessageActivity>) -> Void)?
    private var postingOperationQueue: OperationQueue = OperationQueue()
    private var pendingOperationQueue: [ActivityPostOperation] = [ActivityPostOperation]()
    
    
    var userId :String = ""
    var deviceUrl : URL
    var uuid: String = ""
    var accessTokenStr = ""
    
    init(authenticator: Authenticator, diviceUrl: URL) {
        self.authenticator = authenticator
        self.deviceUrl = diviceUrl
        self.uuid = UUID().uuidString
        self.postingOperationQueue.maxConcurrentOperationCount = 1
    }
    
    // MARK: Encryption Feature Functions
    public func receiNewMessageActivity( messageActivity: MessageActivity){
        self.receivedActivityQueue.append(messageActivity)
        if self.roomResources.filter({$0.conversationID == messageActivity.conversationId}).first == nil{
            let roomModel = ActivityRoomResource(conversationId: messageActivity.conversationId!)
            self.roomResources.append(roomModel)
        }
        if(self.userId == ""){
            self.requestUserId()
        }else if(self.kmsCluster == nil){
            self.requestClusterInfo()
        }else if(!self.ephemeralKeyFetched){
            self.requestEphemeralKey()
        }else{
            if let _ = self.roomResources.filter({$0.encryptionUrl == messageActivity.encryptionKeyUrl!}).first?.keyMaterial {
                self.processReceivedMessageActivity(messageActivity)
            }else{
                self.requestKeyMaterialFor(messageActivity.encryptionKeyUrl!)
            }
        }
    }
    
    public func postNewMessageActivity(messageActivity: MessageActivity){
        if(self.userId == ""){
            self.requestUserId()
        }else if(self.kmsCluster == nil){
            self.requestClusterInfo()
        }else if(!self.ephemeralKeyFetched){
            self.requestEphemeralKey()
        }else{
            self.requestConversationDetail(convasationId: messageActivity.conversationId!)
        }
    }
    
    public func receiveKmsMessage( _ kmsMessageModel: KmsMessageModel){
        if(self.ephemeralKeyRequest == nil && self.ephemeralKeyFetched){
            /// receive decryption key message
            do{
                let responseStr = kmsMessageModel.kmsMessageStrs?.first!
                let kmsMessageData = try CjoseWrapper.content(fromCiphertext: responseStr, key: self.ephemeralKeyStr)
                let kmsMessageJson = JSON(data: kmsMessageData)
                let keyDict = kmsMessageJson["key"].object
                guard let dict = keyDict as? [String:Any] else{
                    throw NSError(domain: "error", code: 0, userInfo: nil)
                }
                if let keyMaterial = JSON(dict["jwk"]!).rawString(),
                    let keyUri = JSON(dict["uri"]!).rawString(){
                    if let room = self.roomResources.filter({$0.encryptionUrl == keyUri}).first{
                        room.keyMaterial = keyMaterial
                        self.processMessageActivitiesWithEncrptionUrl(keyUri)
                    }
                }
            }catch let error as NSError {
                SDKLogger.shared.debug("Error - Receive KmsMessage: \(error.debugDescription)")
            }
        }else{
            /// receive ephemaral key message
            do{
                let responseStr = kmsMessageModel.kmsMessageStrs?.first!
                let kmsresponse = try KmsEphemeralKeyResponse(responseMessage: responseStr, request: self.ephemeralKeyRequest!)
                self.ephemeralKeyStr = kmsresponse.jwkEphemeralKey
                self.ephemeralKeyFetched = true
                self.ephemeralKeyRequest = nil
                if let receveiMessage = self.receivedActivityQueue.first{
                    self.requestKeyMaterialFor(receveiMessage.encryptionKeyUrl!)
                }
                if let postingMessage = self.pendingOperationQueue.first?.messageActivity{
                    self.requestConversationDetail(convasationId: postingMessage.conversationId!)
                }
                
            }catch let error as NSError {
                SDKLogger.shared.debug("Error - Receive EpheMeralKMS: \(error.debugDescription)")
            }
        }
    }
    
    private func processReceivedMessageActivity(_ messageActivity: MessageActivity){
        guard let acitivityKeyMaterial = self.roomResources.filter({$0.encryptionUrl == messageActivity.encryptionKeyUrl!}).first?.keyMaterial else{
            return
        }
        _ = self.receivedActivityQueue.removeObject(equality: { $0.activityId == messageActivity.activityId })
        do {
            guard let chiperText = messageActivity.plainText
                else{
                    return;
            }
            let plainTextData = try CjoseWrapper.content(fromCiphertext: chiperText, key: acitivityKeyMaterial)
            let clearText = NSString(data:plainTextData ,encoding: String.Encoding.utf8.rawValue)
            messageActivity.plainText = clearText! as String
            messageActivity.markDownString()
            self.onMessageActivity?(messageActivity)
        }catch let error as NSError {
            SDKLogger.shared.debug("Process Activity Error - \(error.description)")
        }
    }
    
    private func processMessageActivitiesWithEncrptionUrl( _ encryptionUrl: String){
        let receivePendingActivityArray = self.receivedActivityQueue.filter({$0.encryptionKeyUrl == encryptionUrl})
        for activity in receivePendingActivityArray{
            self.processReceivedMessageActivity(activity)
        }
        let postPendingActivityArray = self.pendingOperationQueue.filter({$0.messageActivity.encryptionKeyUrl == encryptionUrl})
        let keyMaterial = self.roomResources.filter({$0.encryptionUrl == encryptionUrl}).first?.keyMaterial
        for pendingOperation in postPendingActivityArray{
            pendingOperation.keyMaterial = keyMaterial
            self.postingOperationQueue.addOperation(pendingOperation)
            self.pendingOperationQueue.removeObject(pendingOperation)
        }
    }
    
    private func requestEphemeralKey(){
        self.authenticator.accessToken { (res) in
            self.accessTokenStr = res!
        }
        do{
            guard let clusterUri = self.kmsCluster
                else {
                    return
            }
            let kmsClusterUri = clusterUri + "/ecdhe"
            self.ephemeralKeyRequest = try KmsEphemeralKeyRequest(requestId: self.uuid, clientId: self.deviceUrl.absoluteString , userId: self.userId, bearer: self.accessTokenStr , method: "create", uri: kmsClusterUri, kmsStaticKey: self.rsaPublicKey!)
            
            guard let message = self.ephemeralKeyRequest?.message
                else {
                    return
            }
            
            let parameters : [String: String] = ["kmsMessages" : message, "destination" : clusterUri]
            let header : [String: String]  = ["Cisco-Request-ID" : self.uuid,
                                              "Authorization" : "Bearer " + self.accessTokenStr]
            
            let url = URL(string: kmsMessageServerUri)
            Alamofire.request(url!, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: header).responseString(completionHandler: { (response) in
                SDKLogger.shared.debug("\(response) - RequestEphemeralKey")
            })
        }catch let error as NSError{
            SDKLogger.shared.debug("Error - RequestEphemeralKey \(error.description)")
        }
    }
    
    
    private func requestKeyMaterialFor(_ encryptionUrl: String){
        do{
            let requestedKmsRequest = self.kmsRequestQueue.filter({$0.uri == encryptionUrl})
            if(requestedKmsRequest.count > 0){
                return;
            }
            let kmsRequest = try KmsRequest(requestId: self.uuid, clientId: self.deviceUrl.absoluteString , userId: self.userId, bearer: self.accessTokenStr, method: "retrieve", uri: encryptionUrl)
            let serrizeData = kmsRequest.serialize()
            let chiperText = try CjoseWrapper.ciphertext(fromContent: serrizeData?.data(using: .utf8), key: self.ephemeralKeyStr)
            let kmsMessages = [chiperText]
            let parameters = ["kmsMessages" : kmsMessages, "destination" : "unused" ] as [String : Any]
            let header : [String: String]  = ["Cisco-Request-ID" : self.uuid,
                                              "Authorization" : "Bearer " + self.accessTokenStr]
            let url = URL(string: kmsMessageServerUri)
            Alamofire.request(url!, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: header).responseString(completionHandler: { (response) in
                switch response.result{
                case .success:
                    self.kmsRequestQueue.append(kmsRequest)
                    break
                case .failure(let error):
                    SDKLogger.shared.debug("Error - requestKeyMaterial: \(error.localizedDescription)")
                    break
                }
            })
        }catch let errror as NSError{
            SDKLogger.shared.debug("Error - requestKeyMaterial: \(errror.description)")
        }
    }
    
    
    private func requestConversationDetail(convasationId: String){
        let query = "/conversations/" + convasationId + "?includeActivities=false&includeParticipants=false"
        let url = URL(string: ServiceRequest.CONVERSATION_SERVER_ADDRESS + query)
        let header : [String: String]  = [ "Authorization" : "Bearer " + self.accessTokenStr]
        Alamofire.request(url!, method: .get, parameters: nil, encoding: JSONEncoding.default, headers: header).responseJSON(completionHandler: { (response) in
            switch response.result {
            case .success(let value):
                guard let responseDict = value as? [String: Any]
                    else{
                        return
                }
                if(responseDict["encryptionKeyUrl"] != nil) {
                    let encryptionUrl = responseDict["encryptionKeyUrl"]
                    let postPendingOperations = self.pendingOperationQueue.filter({$0.messageActivity.conversationId == convasationId})
                    for pendingOperation in postPendingOperations{
                        pendingOperation.messageActivity.encryptionKeyUrl = encryptionUrl as? String
                    }
                    self.requestKeyMaterialFor(encryptionUrl as! String)
                }
                break
            case .failure:
                break
            }
        })
    }
    
    private func requestUserId(){
        let request = userInfoRequestBuilder().path("users")
            .method(.get)
            .build()
        request.responseJSON{ (response: ServiceResponse<Any>) in
            switch response.result {
            case .success(let value):
                guard let responseDict = value as? [String: Any]
                    else{
                        return;
                }
                self.userId = responseDict["id"]! as! String
                self.requestClusterInfo()
                break
            case .failure:
                break
            }
        }
    }
    
    private func requestClusterInfo(){
        let request = kmsRequestBuilder().path("kms")
            .method(.get)
            .build()
        request.responseJSON{ (response: ServiceResponse<Any>) in
            switch response.result {
            case .success(let value):
                guard let responseDict = value as? [String: String]
                    else{
                        return;
                }
                self.kmsCluster = responseDict["kmsCluster"]
                self.rsaPublicKey = responseDict["rsaPublicKey"]
                self.requestEphemeralKey()
                break
            case .failure:
                break
            }
        }
    }
}

extension Array {
    mutating func removeObject(equality: (Element) -> Bool) -> Element? {
        for (idx, element) in self.enumerated() {
            if equality(element) {
                return self.remove(at: idx);
            }
        }
        return nil
    }
}

