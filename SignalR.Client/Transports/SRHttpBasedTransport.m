//
//  SRHttpBasedTransport.m
//  SignalR
//
//  Created by Alex Billingsley on 1/7/12.
//  Copyright (c) 2011 DyKnow LLC. (http://dyknow.com/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and 
//  to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of 
//  the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
//  THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF 
//  CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
//  DEALINGS IN THE SOFTWARE.
//

#import <AFNetworking/AFNetworking.h>
#import "SRConnectionInterface.h"
#import "SRHttpBasedTransport.h"
#import "SRLog.h"
#import "SRNegotiationResponse.h"

#import "NSObject+SRJSON.h"

@interface SRHttpBasedTransport()

@property (assign, nonatomic, readwrite) BOOL startedAbort;

@end

@implementation SRHttpBasedTransport

#pragma mark
#pragma mark SRClientTransportInterface

- (NSString *)name {
    return @"";
}

- (BOOL)supportsKeepAlive {
    return NO;
}

- (void)negotiate:(id<SRConnectionInterface>)connection connectionData:(NSString *)connectionData completionHandler:(void (^)(SRNegotiationResponse * response, NSError *error))block {
    
    id parameters = @{
        @"clientProtocol" : connection.protocol,
        @"connectionData" : (connectionData) ? connectionData : @"",
    };
    
    if ([connection queryString]) {
        NSMutableDictionary *_parameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
        [_parameters addEntriesFromDictionary:[connection queryString]];
        parameters = _parameters;
    }
    
    NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] requestWithMethod:@"GET" URLString:[connection.url stringByAppendingString:@"negotiate"] parameters:parameters error:nil];
    [connection prepareRequest:request]; //TODO: prepareRequest
    [request setTimeoutInterval:30];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setResponseSerializer:[AFJSONResponseSerializer serializer]];
    //operation.shouldUseCredentialStorage = self.shouldUseCredentialStorage;
    //operation.credential = self.credential;
    //operation.securityPolicy = self.securityPolicy;
    AFSecurityPolicy *securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
    [securityPolicy setAllowInvalidCertificates:YES];
    operation.securityPolicy= securityPolicy;

    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        if(block) {
            block([[SRNegotiationResponse alloc] initWithDictionary:responseObject], nil);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if(block) {
            block(nil, error);
        }
    }];
    [operation start];
}

- (void)start:(id<SRConnectionInterface>)connection connectionData:(NSString *)connectionData completionHandler:(void (^)(id response, NSError *error))block {
}

- (void)send:(id<SRConnectionInterface>)connection data:(NSString *)data connectionData:(NSString *)connectionData completionHandler:(void (^)(id response, NSError *error))block {
    id parameters = @{
        @"transport" : [self name],
        @"connectionData" : (connectionData) ? connectionData : @"",
        @"connectionToken" : [connection connectionToken],
    };
    
    if ([connection queryString]) {
        NSMutableDictionary *_parameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
        [_parameters addEntriesFromDictionary:[connection queryString]];
        parameters = _parameters;
    }
    
    //TODO: this is a little strange but SignalR Expects the parameters in the queryString and fails if in the body.
    //So we let AFNetworking Generate our URL with proper encoding and then create the POST url which will encode the data in the body.
    NSMutableURLRequest *url = [[AFHTTPRequestSerializer serializer] requestWithMethod:@"GET" URLString:[connection.url stringByAppendingString:@"send"] parameters:parameters error:nil];
    NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] requestWithMethod:@"POST" URLString:[[url URL] absoluteString] parameters:@{ @"data" : data } error:nil];
    [connection prepareRequest:request]; //TODO: prepareRequest
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setResponseSerializer:[AFJSONResponseSerializer serializer]];
    //operation.shouldUseCredentialStorage = self.shouldUseCredentialStorage;
    //operation.credential = self.credential;
    //operation.securityPolicy = self.securityPolicy;
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        [connection didReceiveData:responseObject];
        if(block) {
            block(responseObject, nil);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [connection didReceiveError:error];
        if (block) {
            block(nil, error);
        }
    }];
    [operation start];
}

- (void)completeAbort {
    // Make any future calls to Abort() no-op
    // Abort might still run, but any ongoing aborts will immediately complete
    _startedAbort = YES;
}

- (BOOL)tryCompleteAbort {
    if (_startedAbort) {
        return YES;
    } else {
        return NO;
    }
}

- (void)lostConnection:(id<SRConnectionInterface>)connection {
    //TODO: Throw, Subclass should implement this.
}

- (void)abort:(id<SRConnectionInterface>)connection timeout:(NSNumber *)timeout connectionData:(NSString *)connectionData {

    // Ensure that an abort request is only made once
    if (!_startedAbort)
    {
        SRLogHTTPTransport(@"will stop transport");
        _startedAbort = YES;
        
        id parameters = @{
            @"transport" : [self name],
            @"connectionData" : (connectionData) ? connectionData : @"",
            @"connectionToken" : [connection connectionToken],
        };
        
        if ([connection queryString]) {
            NSMutableDictionary *_parameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
            [_parameters addEntriesFromDictionary:[connection queryString]];
            parameters = _parameters;
        }
        
        NSMutableURLRequest *url = [[AFHTTPRequestSerializer serializer] requestWithMethod:@"GET" URLString:[connection.url stringByAppendingString:@"abort"] parameters:parameters error:nil];
        NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] requestWithMethod:@"POST" URLString:[[url URL] absoluteString] parameters:nil error:nil];
        [connection prepareRequest:request]; //TODO: prepareRequest
        [request setTimeoutInterval:2];
        AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
        [operation setResponseSerializer:[AFJSONResponseSerializer serializer]];
        //operation.shouldUseCredentialStorage = self.shouldUseCredentialStorage;
        //operation.credential = self.credential;
        //operation.securityPolicy = self.securityPolicy;
        [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            SRLogHTTPTransport(@"Clean disconnect failed. %@",error);
            [self completeAbort];
        }];
        [operation start];
    }
}

- (void)processResponse:(id <SRConnectionInterface>)connection
               response:(NSString *)response
        shouldReconnect:(BOOL *)shouldReconnect
           disconnected:(BOOL *)disconnected {

    [connection updateLastKeepAlive];
    
    *shouldReconnect = NO;
    *disconnected = NO;
    
    if(response == nil || [response isEqualToString:@""]) {
        return;
    }
    
    id result = [response SRJSONValue];
    if([result isKindOfClass:[NSDictionary class]]) {
        if (result[@"I"] != nil) {
            [connection didReceiveData:result];
            return;
        }
        
        *shouldReconnect = [result[@"T"] boolValue];
        *disconnected = [result[@"D"] boolValue];
        
        if(*disconnected) {
            return;
        }
        
        NSString *groupsToken = result[@"G"];
        if (groupsToken) {
            connection.groupsToken = groupsToken;
        }
        
        id messages = result[@"M"];
        if(messages && [messages isKindOfClass:[NSArray class]]) {
            connection.messageId = result[@"C"];
            
            for (id message in messages) {
                [connection didReceiveData:message];
            }
            
            if ([result[@"S"] boolValue]) {
                //TODO: Call Initialized Callback
                //onInitialized();
            }
        }
    }
}

@end
