//
//  BLWebSocketServer.m
//  LibWebSocket
//
//  Created by Benjamin Loulier on 1/22/13.
//  Copyright (c) 2013 Benjamin Loulier. All rights reserved.
//

#import "BLWebSocketsServer.h"

static int pollingInterval = 20;
static char * http_only_protocol = "http-only";

static BLWebSocketsHandleRequestBlock _handleRequestBlock = NULL;
/* Context representing the server */
static struct libwebsocket_context *context;

/* Declaration of the callbacks (http and websockets), libwebsockets requires an http callback even if we don't use it*/
static int callback_websockets(struct libwebsocket_context * this,
             struct libwebsocket *wsi,
             enum libwebsocket_callback_reasons reason,
             void *user, void *in, size_t len);


static int callback_http(struct libwebsocket_context *context,
                         struct libwebsocket *wsi,
                         enum libwebsocket_callback_reasons reason, void *user,
                         void *in, size_t len);

@interface BLWebSocketsServer()

/*Using atomic in our case is sufficient to ensure thread safety*/
@property (atomic, assign, readwrite) BOOL isRunning;
@property (atomic, assign) BOOL stopServer;

- (void)cleanup;

@end

@implementation BLWebSocketsServer

#pragma mark - Shared instance
+ (BLWebSocketsServer *)sharedInstance {
    static BLWebSocketsServer *sharedServer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedServer = [[self alloc] init];
    });
    return sharedServer;
}

#pragma mark - Custom getters and setters
- (void)setHandleRequestBlock:(BLWebSocketsHandleRequestBlock)block {
    _handleRequestBlock = block;
}

#pragma mark - Server management
- (void)startListeningOnPort:(int)port withProtocolName:(NSString *)protocolName {
    
    if (self.isRunning) {
        return;
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
        
    dispatch_async(queue, ^{
        
        /* Context creation */
        struct libwebsocket_protocols protocols[] = {
            /* first protocol must always be HTTP handler */
            {
                http_only_protocol,
                callback_http,
                0
            },
            {
                [protocolName cStringUsingEncoding:NSASCIIStringEncoding],
                callback_websockets,   // callback
                0            // we don't use any per session data
                
            },
            {
                NULL, NULL, 0   /* End of list */
            }
        };
        context = libwebsocket_create_context(port, NULL, protocols,
                                              libwebsocket_internal_extensions,
                                              NULL, NULL, NULL, -1, -1, 0, NULL);
        
        if (context == NULL) {
            NSLog(@"Initialization of the websockets server failed");
        }
        else {
            self.isRunning = YES;
            
            /* For now infinite loop which proceses events and wait for n ms. */
            while (!self.stopServer) {
                libwebsocket_service(context, pollingInterval);
            }
            
            [self cleanup];
            
            self.isRunning = NO;
        }
        
    });
    
}

- (void)stop {
    
    if (!self.isRunning) {
        return;
    }
    else {
        self.stopServer = YES;
    }
}

- (void)cleanup {
    libwebsocket_context_destroy(context);
    context = NULL;
    self.stopServer = NO;
    [self setHandleRequestBlock:NULL];
}

@end

/* Implementation of the callbacks (http and websockets) */
static int callback_websockets(struct libwebsocket_context * this,
             struct libwebsocket *wsi,
             enum libwebsocket_callback_reasons reason,
             void *user, void *in, size_t len) {
    switch (reason) {
        case LWS_CALLBACK_ESTABLISHED:
            NSLog(@"%@", @"Connection established");
            break;
        case LWS_CALLBACK_RECEIVE: {
            unsigned char *response_buf;
            NSData *data = [NSData dataWithBytes:(const void *)in length:len];
            NSData *response = nil;
            if (_handleRequestBlock) {
                response = _handleRequestBlock(data);
            }
            response_buf = (unsigned char*) malloc(LWS_SEND_BUFFER_PRE_PADDING + response.length +LWS_SEND_BUFFER_POST_PADDING);
            bcopy([response bytes], &response_buf[LWS_SEND_BUFFER_PRE_PADDING], response.length);
            libwebsocket_write(wsi, &response_buf[LWS_SEND_BUFFER_PRE_PADDING], response.length, LWS_WRITE_TEXT);
            free(response_buf);
            break;
        }
        default:
            break;
    }
    
    return 0;
}

static int callback_http(struct libwebsocket_context *context,
                         struct libwebsocket *wsi,
                         enum libwebsocket_callback_reasons reason, void *user,
                         void *in, size_t len)
{
    return 0;
}


