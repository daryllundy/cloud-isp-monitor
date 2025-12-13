import os
import ssl
import unittest
from unittest.mock import patch, MagicMock, call
from io import StringIO
import sys

# Import the module to test
import heartbeat_agent

class TestHeartbeatAgentConfig(unittest.TestCase):
    
    def setUp(self):
        # Clear env vars before each test
        self.original_env = os.environ.copy()
        if 'HEARTBEAT_URL' in os.environ:
            del os.environ['HEARTBEAT_URL']
        if 'HEARTBEAT_DEVICE' in os.environ:
            del os.environ['HEARTBEAT_DEVICE']

    def tearDown(self):
        # Restore env vars
        os.environ.clear()
        os.environ.update(self.original_env)

    @patch('sys.stderr', new_callable=StringIO)
    def test_missing_url_error(self, mock_stderr):
        """Test that missing URL causes error exit."""
        test_args = ['heartbeat_agent.py']
        with patch.object(sys, 'argv', test_args):
            with self.assertRaises(SystemExit) as cm:
                heartbeat_agent.main()
            self.assertEqual(cm.exception.code, 1)
            self.assertIn("Error: No URL specified", mock_stderr.getvalue())

    def test_url_from_env(self):
        """Test URL is picked up from environment variable."""
        os.environ['HEARTBEAT_URL'] = 'https://example.com/api'
        self.assertEqual(heartbeat_agent.get_endpoint_url(), 'https://example.com/api')

    @patch('heartbeat_agent.send_ping')
    def test_url_from_cli_overrides_env(self, mock_send_ping):
        """Test CLI argument overrides environment variable."""
        os.environ['HEARTBEAT_URL'] = 'https://env-url.com'
        test_args = ['heartbeat_agent.py', '--url', 'https://cli-url.com', '--once']
        
        mock_send_ping.return_value = True
        
        with patch.object(sys, 'argv', test_args):
            try:
                heartbeat_agent.main()
            except SystemExit:
                pass
            
            mock_send_ping.assert_called_with('https://cli-url.com', unittest.mock.ANY, note=unittest.mock.ANY, verbose=unittest.mock.ANY)

    @patch('sys.stderr', new_callable=StringIO)
    def test_invalid_url_protocol(self, mock_stderr):
        """Test that non-http/https URL causes error."""
        test_args = ['heartbeat_agent.py', '--url', 'ftp://example.com']
        with patch.object(sys, 'argv', test_args):
            with self.assertRaises(SystemExit) as cm:
                heartbeat_agent.main()
            self.assertEqual(cm.exception.code, 1)
            self.assertIn("Error: URL must start with http:// or https://", mock_stderr.getvalue())

    def test_https_enforcement(self):
        """Test that HTTPS URLs are accepted."""
        test_args = ['heartbeat_agent.py', '--url', 'https://example.com', '--once']
        
        with patch('heartbeat_agent.send_ping') as mock_send_ping:
            mock_send_ping.return_value = True
            
            with patch.object(sys, 'argv', test_args):
                try:
                    heartbeat_agent.main()
                except SystemExit as e:
                    # Should exit with 0 (success)
                    self.assertEqual(e.code, 0)
                
                # Verify send_ping was called with HTTPS URL
                mock_send_ping.assert_called_once()
                call_args = mock_send_ping.call_args
                self.assertTrue(call_args[0][0].startswith('https://'))

    @patch('heartbeat_agent.urlopen')
    @patch('heartbeat_agent.ssl.create_default_context')
    def test_ssl_verification_enabled(self, mock_ssl_context, mock_urlopen):
        """Test that SSL certificate verification is enabled."""
        # Setup mock SSL context
        mock_context = MagicMock()
        mock_ssl_context.return_value = mock_context
        
        # Setup mock response
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read.return_value = b'ok'
        mock_response.__enter__ = MagicMock(return_value=mock_response)
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response
        
        # Send a ping
        result = heartbeat_agent.send_ping('https://example.com', 'test-device', verbose=False)
        
        # Verify SSL context was created with default (secure) settings
        mock_ssl_context.assert_called_once()
        
        # Verify urlopen was called with the SSL context
        mock_urlopen.assert_called_once()
        call_kwargs = mock_urlopen.call_args[1]
        self.assertIn('context', call_kwargs)
        self.assertEqual(call_kwargs['context'], mock_context)
        
        # Verify the ping was successful
        self.assertTrue(result)

if __name__ == '__main__':
    unittest.main()
