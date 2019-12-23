--
-- (C) 2019 - ntop.org
--
dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/?.lua;" .. package.path
if((dirs.scriptdir ~= nil) and (dirs.scriptdir ~= "")) then package.path = dirs.scriptdir .. "/lua/modules/?.lua;" .. package.path end
ignore_post_payload_parse = 1

local dialogflow = require "nAssistant/dialogflow_APIv2"
local handlers = require "nAssistant/handlers"

local user_request, ntop_response = dialogflow.receive(), {}
------------------------
------------------------

if  user_request.queryResult.intent.displayName == "ask_for_host_info - fallback" then
    ntop_response = handlers.host_info(user_request)

elseif  user_request.queryResult.intent.displayName == "ask_for_host_info - fallback - more" then
    ntop_response = handlers.host_info_more(user_request)

------------------------
elseif  user_request.queryResult.intent.displayName == "if_active_flow_top_application" then
    ntop_response = handlers.if_active_flow_top_application(user_request)

elseif  user_request.queryResult.intent.displayName == "if_active_flow_top_categories"  then
    ntop_response = handlers.if_active_flow_top_categories(user_request)

------------------------
elseif  user_request.queryResult.intent.displayName == "who_is - categories" then
    ntop_response = handlers.who_is_categories(user_request)

elseif  user_request.queryResult.intent.displayName == "who_is - protocols"  then
    ntop_response = handlers.who_is_protocols(user_request)

------------------------
elseif  user_request.queryResult.intent.displayName == "who_is - categories - fallback" then
    ntop_response = handlers.host_info(user_request)

elseif  user_request.queryResult.intent.displayName == "who_is - protocols - fallback" then
    ntop_response = handlers.host_info(user_request) 

------------------------
elseif  user_request.queryResult.intent.displayName == "get_security_info" then
    ntop_response = handlers.get_security_info(user_request)

elseif  user_request.queryResult.intent.displayName == "get_security_info - fallback" then
    ntop_response =handlers.host_info(user_request) 

elseif  user_request.queryResult.intent.displayName == "get_security_info - fallback - more" then
    ntop_response = handlers.host_info_more(user_request)

------------------------
elseif  user_request.queryResult.intent.displayName == "get_suspected_host_info" then
    ntop_response = handlers.get_most_suspected_host_info(user_request)

elseif  user_request.queryResult.intent.displayName == "get_host_misbehaving_flows_info" then
    ntop_response = handlers.get_host_misbehaving_flows_info(user_request) 

else ntop_response = dialogflow.send("Sorry, but I didn't understand, can you repeat please?") 
end

dialogflow.send(
    ntop_response.speech_text,
    ntop_response.display_text,
    ntop_response.suggestions,
    ntop_response.card
)

--[[




{
	"version": "1.0",
	"session": {
		"new": false,
		"sessionId": "amzn1.echo-api.session.595a3c65-a478-4f05-84ab-7ff7f7300ee9",
		"application": {
			"applicationId": "amzn1.ask.skill.1a6dd79a-2661-4d7a-97ef-4733a26e9a86"
		},
		"user": {
			"userId": "amzn1.ask.account.AEHO2MGQ6OMQXY27GC3YNBSZC25SK4VXFR67WOINWPSLF53QR57GWKIYB7K4NDUGD5VWVB3JYBDSTGGYHYJBNUPI2DAO3BXJ2CF7WKYVIP54EYGKOQDN3WCYNXROKMYAATUSDC2JYWYAHGMYM52CD7QRFAMIYPNHE6QK4QS3LTVREW4HVJEQFT737BPL7Y7UYAB4BFHOCW7GQHI"
		}
	},
	"context": {
		"System": {
			"application": {
				"applicationId": "amzn1.ask.skill.1a6dd79a-2661-4d7a-97ef-4733a26e9a86"
			},
			"user": {
				"userId": "amzn1.ask.account.AEHO2MGQ6OMQXY27GC3YNBSZC25SK4VXFR67WOINWPSLF53QR57GWKIYB7K4NDUGD5VWVB3JYBDSTGGYHYJBNUPI2DAO3BXJ2CF7WKYVIP54EYGKOQDN3WCYNXROKMYAATUSDC2JYWYAHGMYM52CD7QRFAMIYPNHE6QK4QS3LTVREW4HVJEQFT737BPL7Y7UYAB4BFHOCW7GQHI"
			},
			"device": {
				"deviceId": "amzn1.ask.device.AFECFBIGF7OII3EVTMRMJRI7LVQHHGCYPJKB64WOMEHD5525GDJSJMXKLS64O4MZ3SC7Z4PHKHHMK5YS3ZYXL2URMGNXD5J3PQTZWJD3GPCPWK4HFDIFEQTWU7UFSLTXFNCVSPZHTYFFZ7PBSCIUPVOKJ3DHW3WZGNSFKTVIV4DTE4SUBNXN2",
				"supportedInterfaces": {}
			},
			"apiEndpoint": "https://api.amazonalexa.com",
			"apiAccessToken": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6IjEifQ.eyJhdWQiOiJodHRwczovL2FwaS5hbWF6b25hbGV4YS5jb20iLCJpc3MiOiJBbGV4YVNraWxsS2l0Iiwic3ViIjoiYW16bjEuYXNrLnNraWxsLjFhNmRkNzlhLTI2NjEtNGQ3YS05N2VmLTQ3MzNhMjZlOWE4NiIsImV4cCI6MTU3NzA0NTk0NSwiaWF0IjoxNTc3MDQ1NjQ1LCJuYmYiOjE1NzcwNDU2NDUsInByaXZhdGVDbGFpbXMiOnsiY29udGV4dCI6IkFBQUFBQUFBQUFEdUVuM3JmY1MzRXd1d2ZjZ3hnR3JLS3dFQUFBQUFBQUFSWkJoVzc4UzA3M2Q0SUN2VGUycEgxV1d2UmxKZWRCOHhJNzk1RjJNMzlrbTlnQkZYcU5xMEpydS9zS3ZMUVh2K3MyUHo1MFpBd1p5SzZiRFZlZnJUbmRjNUU1QmNlUDZwalNqenhxbXlaMlk0SDhQNTdta0JXSlI0b3VxNDRMdDVQbVVqMzN0THhYZzRCcUkwUzlaVTlRaWJYZ0ljN0hkL1M4WVE1MmNoR1RIVlVxREZKb1U5RjBSNks2MWdhQUw5OFRVeGZqdzNmM2NKZDlvb2JQZUJxTjdIMllZWU5SRzhIdEZFbkxVdWNQYk5mQll2S2lGU28wRXJTbnY1cGtLTlVSR1ppdTBhTzh3WGF0dHdEZGRGK0VyNFlwNHlrMHRqQWlNdGE2c0s0dUNLNGtZbXdlQ3pYN0d2OGtrRUR5WThKK2NrUlZ1SkIrenBFcDhsQXFRQk01ZTVqck1VYy9PMGc2TE5UcTd0ck5UeGtubUs5TWdnWUZxeWgzaUZLM3NDLzg4WlVERk51bUovSnc9PSIsImNvbnNlbnRUb2tlbiI6bnVsbCwiZGV2aWNlSWQiOiJhbXpuMS5hc2suZGV2aWNlLkFGRUNGQklHRjdPSUkzRVZUTVJNSlJJN0xWUUhIR0NZUEpLQjY0V09NRUhENTUyNUdESlNKTVhLTFM2NE80TVozU0M3WjRQSEtISE1LNVlTM1pZWEwyVVJNR05YRDVKM1BRVFpXSkQzR1BDUFdLNEhGRElGRVFUV1U3VUZTTFRYRk5DVlNQWkhUWUZGWjdQQlNDSVVQVk9LSjNESFczV1pHTlNGS1RWSVY0RFRFNFNVQk5YTjIiLCJ1c2VySWQiOiJhbXpuMS5hc2suYWNjb3VudC5BRUhPMk1HUTZPTVFYWTI3R0MzWU5CU1pDMjVTSzRWWEZSNjdXT0lOV1BTTEY1M1FSNTdHV0tJWUI3SzRORFVHRDVWV1ZCM0pZQkRTVEdHWUhZSkJOVVBJMkRBTzNCWEoyQ0Y3V0tZVklQNTRFWUdLT1FETjNXQ1lOWFJPS01ZQUFUVVNEQzJKWVdZQUhHTVlNNTJDRDdRUkZBTUlZUE5IRTZRSzRRUzNMVFZSRVc0SFZKRVFGVDczN0JQTDdZN1VZQUI0QkZIT0NXN0dRSEkifX0.MqZJFi0IhjNm6JnbGGo0xEQxxHFXWPFZueegyO09QFxQLO-TIAauUmVo4va0C6hR8qCP_fFoA_qUd0H6SXyL64uxn2LfaNYYFZr7l9EdemHtVL0wowFggrfR2OGvacAOVMv7u7VmVyYPEzRfRhyOTfMkOe-GV2u1C4Y1fENXIa3RNbvTMydQ-YH42xxPSBDRMLf2VVnQ2khK8RKPSE7vuGiAf3oz-9iNfIgzTH5k8usUIMGBzAIPXIi4wFqz0X3zk31UpOeuQQdS8LTWkPUkCc2_1y-wZefRkinzhLOwb-xAHXVkqoelH6k1A9c16n97-oEY5aEHekckDvRN8VgMnA"
		},
		"Viewport": {
			"experiences": [
				{
					"arcMinuteWidth": 246,
					"arcMinuteHeight": 144,
					"canRotate": false,
					"canResize": false
				}
			],
			"shape": "RECTANGLE",
			"pixelWidth": 1024,
			"pixelHeight": 600,
			"dpi": 160,
			"currentPixelWidth": 1024,
			"currentPixelHeight": 600,
			"touch": [
				"SINGLE"
			],
			"video": {
				"codecs": [
					"H_264_42",
					"H_264_41"
				]
			}
		},
		"Viewports": [
			{
				"type": "APL",
				"id": "main",
				"shape": "RECTANGLE",
				"dpi": 160,
				"presentationType": "STANDARD",
				"canRotate": false,
				"configuration": {
					"current": {
						"video": {
							"codecs": [
								"H_264_42",
								"H_264_41"
							]
						},
						"size": {
							"type": "DISCRETE",
							"pixelWidth": 1024,
							"pixelHeight": 600
						}
					}
				}
			}
		]
	},
	"request": {
		"type": "SessionEndedRequest",
		"requestId": "amzn1.echo-api.request.65fdd6b0-c3bb-4400-98b4-d3cb2974cfa3",
		"timestamp": "2019-12-22T20:14:06Z",
		"locale": "en-US",
		"reason": "ERROR",
		"error": {
			"type": "INVALID_RESPONSE",
			"message": "An exception occurred while dispatching the request to the skill."
		}
	}
}



]]