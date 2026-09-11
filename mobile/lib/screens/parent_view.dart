import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class ParentViewScreen extends StatefulWidget {
  const ParentViewScreen({super.key});

  @override
  State<ParentViewScreen> createState() => _ParentViewScreenState();
}

class _ParentViewScreenState extends State<ParentViewScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<String> _summaries = [];
  List<String> _facts = [];

  @override
  void initState() {
    super.initState();
    _fetchParentData();
  }

  Future<void> _fetchParentData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse('${AppConfig.httpUrl}/api/parent/data'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _summaries = List<String>.from(data['summaries'] ?? []);
          _facts = List<String>.from(data['facts'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Server returned error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load parent data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Parent Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchParentData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF818CF8)),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.amber),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchParentData,
                          child: const Text('Retry'),
                        )
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Facts Section
                    _buildSectionHeader(
                      'Remembered Facts About Child',
                      Icons.star_rounded,
                      Colors.amber,
                    ),
                    const SizedBox(height: 8),
                    if (_facts.isEmpty)
                      _buildEmptyCard('No permanent facts recorded yet.')
                    else
                      ..._facts.map((f) => _buildFactItem(f)),

                    const SizedBox(height: 24),

                    // Summaries Section
                    _buildSectionHeader(
                      'Recent Conversations (Last 3 Days)',
                      Icons.history_rounded,
                      Colors.lightBlueAccent,
                    ),
                    const SizedBox(height: 8),
                    if (_summaries.isEmpty)
                      _buildEmptyCard(
                          'No recent conversation summaries recorded.')
                    else
                      ..._summaries.map((s) => _buildSummaryItem(s)),

                    const SizedBox(height: 32),

                    // Control: Stop/Exit App
                    Center(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.power_settings_new,
                            color: Colors.redAccent),
                        label: const Text(
                          'Close App',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        onPressed: () {
                          SystemNavigator.pop();
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildFactItem(String fact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 18, color: Color(0xFF4ADE80)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fact,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String summary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Text(
        summary,
        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
      ),
    );
  }
}
