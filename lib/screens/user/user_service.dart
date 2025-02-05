import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:mentalwellness/agent/model/agent.model.dart';
import 'package:mentalwellness/screens/chat/model/chat.model.dart';
import 'package:mentalwellness/screens/user/model/user.model.dart';
import 'package:mentalwellness/store/app_logs.dart';
import 'package:mentalwellness/utils/constants.dart';
import 'package:mentalwellness/utils/env.dart';
import 'package:mentalwellness/utils/shared.dart';
import 'package:mentalwellness/utils/toast.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class UserService {
  
  static Future<List<AgentModel>> fetchAgentsList() async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

      try {
          AppLog.log().i('Fetching agents list');

          List<AgentModel> agentsList = [];

          QuerySnapshot querySnapshot = await db.collection("agents").get();
          for (var doc in querySnapshot.docs) {
              print("doc id: ${doc.id} => data: ${doc.data()}");

              Map<String, Object?> agentData = Map<String, Object?>.from(doc.data() as Map);

              agentData['uid'] = doc.id;

              // Convert Timestamp to DateTime
              if (agentData['createdAt'] is Timestamp) {
                  agentData['createdAt'] = (agentData['createdAt'] as Timestamp).toDate().toString();
              }

              print('agentData: $agentData');

              AgentModel agent = AgentModel.fromJson(agentData);
              agentsList.add(agent);
          }

          // Calculate average rating and sort the list
          agentsList.sort((a, b) {
              // Calculate average rating for agent a
              double averageRatingA = double.parse(calculateAverageRating(a.rating));
              // Calculate average rating for agent b
              double averageRatingB = double.parse(calculateAverageRating(b.rating));

              // First, compare by conversation count (descending)
              int conversationComparison = b.conversationCount.compareTo(a.conversationCount);

              if (conversationComparison != 0) {
                  return conversationComparison;
              } else {
                  // If conversation counts are equal, compare by average rating (descending)
                  return averageRatingB.compareTo(averageRatingA);
              }
          });

          print('agentsList: $agentsList');

          return agentsList;
      } catch (e) {
          AppLog.log().e('Error while fetching agents list: $e');
          showToast(message: 'Error while fetching agents list', bgColor: getColor(AppColors.error));
          return Future.error('Error while fetching agents list');
      }
  }

// i will comment out the following code. I tried to build apk and send request (of course i run backend api) but it failed. 
// then i tried with firebase functions. however it seems i run into debt, so i just simply make functions to send request directly to gpt-4o in the frontend.

  // static Future<String> gpt(List<Map<String, String>> messages) async {
  //   try {
  //     final response = await http.post(
  //       Uri.parse('${Environments.backendServiceBaseUrl}/api/gpt4o'),
  //       headers: {
  //         'Content-Type': 'application/json',
  //       },
  //       body: json.encode({'messages': messages}),
  //     );
  //     if (response.statusCode == 200) {
  //       final dynamic data = json.decode(response.body);
  //       print('Generated (GPT ): $data');

  //       String content = data;
  //       return content;
  //     } else {
  //       return Future.error('Failed to generate (GPT)');
  //     }
  //   } catch (e) {
  //     showToast(message: 'An error has occured. Please try again later.', bgColor: getColor(AppColors.error));
  //     AppLog.log().e('Failed to generate (GPT ): $e');
  //     return Future.error('Failed to generate (GPT )');
  //   }
  // }


static Future<String> gpt(List<Map<String, String>> messages) async {
  try {

    final payload = {
      'model': 'gpt-4o',
      'messages': messages,
    };

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ',
      },
      body: json.encode(payload),
    );

    if (response.statusCode == 200) {
      final dynamic data = json.decode(response.body);
      print('Generated (GPT): $data');

      if (data is Map<String, dynamic> && data.containsKey('choices')) {
        final choices = data['choices'] as List<dynamic>;
        if (choices.isNotEmpty && choices[0] is Map<String, dynamic>) {
          final responseText = choices[0]['message']['content'] as String;
          return responseText;
        } else {
          showToast(message: 'An error has occurred. Please try again later.', bgColor: getColor(AppColors.error));
          return Future.error('Failed to generate (GPT): Invalid response format');
        }
      } else {
        showToast(message: 'An error has occurred. Please try again later.', bgColor: getColor(AppColors.error));
        return Future.error('Failed to generate (GPT): Invalid response format');
      }
    } else {
      showToast(message: 'An error has occurred. Please try again later.', bgColor: getColor(AppColors.error));
      return Future.error('Failed to generate (GPT)');
    }
  } catch (e) {
    showToast(message: 'An error has occurred. Please try again later.', bgColor: getColor(AppColors.error));
    print('Failed to generate (GPT): $e');
    return Future.error('Failed to generate (GPT)');
  }
}



  static Future<List<ChatModel>> getUserChats(String userId) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Fetching user chats');

      List<ChatModel> userChats = [];

      // Query Firestore with ordering by createdAt in descending order
      QuerySnapshot querySnapshot = await db.collection('chats')
          .where('userId', isEqualTo: userId)
          .orderBy('updatedAt', descending: true)
          .get();

      for (var doc in querySnapshot.docs) {
        print("doc id: ${doc.id} => data: ${doc.data()}");

        Map<String, Object?> chatData = Map<String, Object?>.from(doc.data() as Map);

        chatData['uid'] = doc.id;

        // Ensure 'chatMessages' is a List
        if (chatData['chatMessages'] == null || chatData['chatMessages'] is! List) {
          chatData['chatMessages'] = [];
        }

        // Convert each message in the list to ChatMessageModel
        List<ChatMessageModel> messages = (chatData['chatMessages'] as List)
            .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
            .toList();

        chatData['chatMessages'] = messages;

        // Convert Timestamp to DateTime
        if (chatData['createdAt'] is Timestamp) {
          chatData['createdAt'] = (chatData['createdAt'] as Timestamp).toDate();
        }
        if (chatData['updatedAt'] is Timestamp) {
          chatData['updatedAt'] = (chatData['updatedAt'] as Timestamp).toDate();
        }

        print('chatData: $chatData');

        ChatModel chat = ChatModel(
          uid: chatData['uid'] as String,
          userId: chatData['userId'] as String,
          agentId: chatData['agentId'] as String,
          messages: messages,
          title: chatData['title'] as String,
          createdAt: chatData['createdAt'] as DateTime,
          updatedAt: chatData['updatedAt'] as DateTime,
        );

        userChats.add(chat);
      }

      print('userChats: $userChats');

      return userChats;
    } catch (e) {
      AppLog.log().e('Error while fetching user chats: $e');
      showToast(message: 'Error while fetching user chats', bgColor: getColor(AppColors.error));
      return Future.error('Error while fetching user chats');
    }
  }


  static Future<List<ChatMessageModel>> addMessageToChat(String chatId, ChatMessageModel newMessage) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Adding new message to chat $chatId');

      DocumentReference chatDocRef = db.collection('chats').doc(chatId);

      return await db.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(chatDocRef);

        if (!snapshot.exists) {
          throw Exception("Chat does not exist!");
        }

        List<dynamic> messages = snapshot.get('chatMessages') as List<dynamic>? ?? [];

        messages.add(newMessage.toJson());

        // Prepare messages for GPT request
        List<Map<String, String>> messageContents = messages.map((msg) {
          var messageMap = msg as Map<String, dynamic>;
          return {
            'role': messageMap['role'] as String,
            'content': messageMap['content'] as String,
          };
        }).toList();

        // Send request to GPT to get the response
        String gptResponse = await gpt(messageContents);

        // Create a new ChatMessageModel for the GPT response
        ChatMessageModel gptMessage = ChatMessageModel(
          role: 'assistant',
          content: gptResponse,
        );

        // Add GPT response to messages
        messages.add(gptMessage.toJson());

        // Update Firestore with both messages
        transaction.update(chatDocRef, {'chatMessages': messages});

        // Convert dynamic list to List<ChatMessageModel>
        List<ChatMessageModel> updatedMessages = messages.map((msg) => ChatMessageModel.fromJson(msg as Map<String, dynamic>)).toList();

        return updatedMessages;
      });
    } catch (e) {
      AppLog.log().e('Error while adding message to chat: $e');
      showToast(message: 'Error while adding message to chat', bgColor: getColor(AppColors.error));
      return Future.error('Error while adding message to chat');
    }
  }


  static Future<ChatModel> createNewChat(ChatModel chat) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Creating a new chat');

      DocumentReference chatDocRef = db.collection('chats').doc();

      Map<String, dynamic> chatData = chat.toJson();
      chatData['uid'] = chatDocRef.id;

      // Convert DateTime to Timestamp before saving
      chatData['createdAt'] = Timestamp.fromDate(chat.createdAt);
      chatData['updatedAt'] = Timestamp.fromDate(chat.updatedAt);

      await chatDocRef.set(chatData);

      // Fetch the created chat document to return it
      DocumentSnapshot createdChatSnapshot = await chatDocRef.get();

      Map<String, dynamic> createdChatData = createdChatSnapshot.data() as Map<String, dynamic>;

      // Convert Timestamp to DateTime after fetching
      if (createdChatData['createdAt'] is Timestamp) {
        createdChatData['createdAt'] = (createdChatData['createdAt'] as Timestamp).toDate();
      }
      if (createdChatData['updatedAt'] is Timestamp) {
        createdChatData['updatedAt'] = (createdChatData['updatedAt'] as Timestamp).toDate();
      }

      ChatModel createdChat = ChatModel.fromJson(createdChatData);
      
      showToast(message: 'New Chat created successfully', bgColor: getColor(AppColors.success));
      return createdChat;
    } catch (e) {
      AppLog.log().e('Error while creating new chat: $e');
      showToast(message: 'Error while creating new chat', bgColor: getColor(AppColors.error));
      return Future.error('Error while creating new chat');
    }
  }

// i will comment out the following code. I tried to build apk and send request (of course i run backend api) but it failed. 
// then i tried with firebase functions. however it seems i run into debt, so i just simply make functions to send request directly to gpt-4o in the frontend.

  // static Future<List<String>> generateTitles(List<ChatMessageModel> messages) async {
  //   try {
  //     List<Map<String, String>> messageContents = messages.map((msg) {
  //       return {
  //         'role': msg.role,
  //         'content': msg.content,
  //       };
  //     }).toList();

  //     final response = await http.post(
  //       Uri.parse('${Environments.backendServiceBaseUrl}/api/gpt4o/title'),
  //       headers: {
  //         'Content-Type': 'application/json',
  //       },
  //       body: json.encode({'messages': messageContents}),
  //     );

  //     if (response.statusCode == 200) {
  //       final dynamic data = json.decode(response.body);
  //       print('Generated data: $data');

  //       if (data is List<dynamic>) {
  //         List<String> titles = data.map((title) => title.toString()).toList();
  //         print('generateTitles: $titles');
  //       return titles;
  //       } else {
  //         showToast(message: "An error has occured while generating titles", bgColor: getColor(AppColors.error));
  //         return Future.error('Failed to generate titles: Invalid response format');
  //       }
  //     } else {
  //       showToast(message: "An error has occured while generating titles", bgColor: getColor(AppColors.error));
  //       return Future.error('Failed to generate titles');
  //     }
  //   } catch (e) {
  //     print('Failed to generate titles: $e');
  //     showToast(message: "An error has occured while generating titles", bgColor: getColor(AppColors.error));
  //     return Future.error('Failed to generate titles');
  //   }
  // }


static Future<List<String>> generateTitles(List<ChatMessageModel> messages) async {
  try {
    List<Map<String, String>> messageContents = messages.map((msg) {
      return {
        'role': msg.role,
        'content': msg.content,
      };
    }).toList();
    final payload = {
      'model': 'gpt-4o',
      'messages': messageContents,
    };

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ',
      },
      body: json.encode(payload),
    );

    // Handle the response
    if (response.statusCode == 200) {
      final dynamic data = json.decode(response.body);
      print('Generated data: $data');

      if (data is Map<String, dynamic> && data.containsKey('choices')) {
        final choices = data['choices'] as List<dynamic>;
        if (choices.isNotEmpty && choices[0] is Map<String, dynamic>) {
          final responseText = choices[0]['message']['content'] as String;
          // Assuming the responseText contains JSON list of titles
          final titlesList = json.decode(responseText.replaceAll("'", '"')) as List<dynamic>;
          List<String> titles = titlesList.map((title) => title.toString()).toList();
          print('generateTitles: $titles');
          return titles;
        } else {
          showToast(message: "An error has occurred while generating titles", bgColor: getColor(AppColors.error));
          return Future.error('Failed to generate titles: Invalid response format');
        }
      } else {
        showToast(message: "An error has occurred while generating titles", bgColor: getColor(AppColors.error));
        return Future.error('Failed to generate titles: Invalid response format');
      }
    } else {
      showToast(message: "An error has occurred while generating titles", bgColor: getColor(AppColors.error));
      return Future.error('Failed to generate titles');
    }
  } catch (e) {
    print('Failed to generate titles: $e');
    showToast(message: "An error has occurred while generating titles", bgColor: getColor(AppColors.error));
    return Future.error('Failed to generate titles');
  }
}




static Future<List<AgentModel>> getMostRatedAgent(int count) async {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  try {
    AppLog.log().i('Fetching most rated agents');

    List<AgentModel> agentsList = [];

    QuerySnapshot querySnapshot = await db.collection("agents").get();
    for (var doc in querySnapshot.docs) {
      print("doc id: ${doc.id} => data: ${doc.data()}");

      Map<String, Object?> agentData = Map<String, Object?>.from(doc.data() as Map);

      agentData['uid'] = doc.id;

      // Convert Timestamp to DateTime
      if (agentData['createdAt'] is Timestamp) {
        agentData['createdAt'] = (agentData['createdAt'] as Timestamp).toDate().toString();
      }

      print('agentData: $agentData');

      AgentModel agent = AgentModel.fromJson(agentData);
      agentsList.add(agent);
    }

    // Calculate average rating for each agent and sort by rating
    agentsList.sort((a, b) {
      double averageRatingA = double.parse(calculateAverageRating(a.rating));
      double averageRatingB = double.parse(calculateAverageRating(b.rating));

      return averageRatingB.compareTo(averageRatingA);
    });

    // Limit the list to the specified number of top-rated agents
    List<AgentModel> topRatedAgents = agentsList.take(count).toList();

    print('topRatedAgents: $topRatedAgents');

    return topRatedAgents;
  } catch (e) {
    AppLog.log().e('Error while fetching most rated agents: $e');
    showToast(message: "An error has occured.", bgColor: getColor(AppColors.error));
    return Future.error('Error while fetching most rated agents');
  }
}


  static Future<AgentModel> getAgentById(String agentId) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Fetching agent by id');

      return db.collection('agents').doc(agentId).get().then((doc) {
        if (doc.exists) {
          Map<String, Object?> agentData = Map<String, Object?>.from(doc.data() as Map);

          agentData['uid'] = doc.id;

          // Convert Timestamp to DateTime
          if (agentData['createdAt'] is Timestamp) {
            agentData['createdAt'] = (agentData['createdAt'] as Timestamp).toDate().toString();
          }

          print('agentData: $agentData');

          return AgentModel.fromJson(agentData);
        } else {
          return Future.error('Agent not found');
        }
      });
    } catch (e) {
      AppLog.log().e('Error while fetching agent by id: $e');
      showToast(message: "An error has occured.", bgColor: getColor(AppColors.error));
      return Future.error('Error while fetching agent by id');
    }
  }

  static Future<void> deleteChatById(String chatId) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Deleting chat by id');

      showToast(message: 'Chat deleted successfully', bgColor: getColor(AppColors.success));
      return db.collection('chats').doc(chatId).delete();
    } catch (e) {
      AppLog.log().e('Error while deleting chat by id: $e');
      showToast(message: 'Error while deleting chat', bgColor: getColor(AppColors.error));
      return Future.error('Error while deleting chat by id');
    }
  }

  static Future<void> updateConversationCount(String agentId) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Updating conversation count for agent $agentId');

      DocumentReference agentDocRef = db.collection('agents').doc(agentId);

      return db.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(agentDocRef);

        if (!snapshot.exists) {
          throw Exception("Agent does not exist!");
        }

        int conversationCount = snapshot.get('conversationCount') as int? ?? 0;

        transaction.update(agentDocRef, {'conversationCount': conversationCount + 1});
      });
    } catch (e) {
      AppLog.log().e('Error while updating conversation count: $e');
      return Future.error('Error while updating conversation count');
    }
  }


  static Future<void> updateRating(String agentId, Map<int, int> rating) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Updating rating for agent $agentId');
      AppLog.log().i('new rating: $rating');

      DocumentReference agentDocRef = db.collection('agents').doc(agentId);

      return db.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(agentDocRef);
        print('snapshot: $snapshot');

        if (!snapshot.exists) {
          throw Exception("Agent does not exist!");
        }
        
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        print('agent data: $data');

        print('data[\'rating\']: ${data['rating']}');
        // print type of data['rating']
        print('type of data[\'rating\']: ${data['rating'].runtimeType}');

        // Convert data['rating'] to Map<int, int>
        Map<int, int> ratings = (data['rating'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(int.parse(key), value as int),
        );

        print('agent ratings: $ratings');

        // Update the ratings
        rating.forEach((key, value) {
          ratings[key] = (ratings[key] ?? 0) + value;
        });

        // Convert ratings back to Map<String, int> for Firestore
        Map<String, int> updatedRatings = ratings.map(
          (key, value) => MapEntry(key.toString(), value),
        );

        print('new ratings: $ratings');

        transaction.update(agentDocRef, {'rating': updatedRatings});
        print('Rating updated successfully');
        showToast(message: 'Thank you for rating', bgColor: getColor(AppColors.success));
      });
    } catch (e) {
      AppLog.log().e('Error while updating rating: $e');
      showToast(message: 'Error while updating rating', bgColor: getColor(AppColors.error));
      return Future.error('Error while updating rating');
    }
  }


  static Future<void> updateConversationTitle(String chatId, String title) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Updating conversation title for chat $chatId');

      DocumentReference chatDocRef = db.collection('chats').doc(chatId);

      showToast(message: 'Chat title updated successfully', bgColor: getColor(AppColors.success));

      return chatDocRef.update({'title': title});
    } catch (e) {
      AppLog.log().e('Error while updating conversation title: $e');
      showToast(message: 'Error while updating conversation title', bgColor: getColor(AppColors.error));
      return Future.error('Error while updating conversation title');
    }
  }

  static Future<UserMetaInfo> getUserMetaInfo(String userId) {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    try {
      AppLog.log().i('Fetching user meta info');

      return db.collection('users').doc(userId).get().then((doc) {
        if (doc.exists) {
          Map<String, Object?> userData = Map<String, Object?>.from(doc.data() as Map);

          userData['uid'] = doc.id;

          // Convert Timestamp to DateTime
          if (userData['createdAt'] is Timestamp) {
            userData['createdAt'] = (userData['createdAt'] as Timestamp).toDate().toString();
          }
          if (userData['updatedAt'] is Timestamp) {
            userData['updatedAt'] = (userData['updatedAt'] as Timestamp).toDate().toString();
          }

          print('userData: $userData');

          return UserMetaInfo.fromJson(userData);
        } else {
          return Future.error('User not found');
        }
      });
    } catch (e) {
      AppLog.log().e('Error while fetching user meta info: $e');
      showToast(message: 'Error while fetching user meta info', bgColor: getColor(AppColors.error));
      return Future.error('Error while fetching user meta info');
    }
  }
}
