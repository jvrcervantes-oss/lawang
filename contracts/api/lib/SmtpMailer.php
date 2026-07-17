<?php
declare(strict_types=1);

/**
 * Cliente SMTP mínimo, sin dependencias (Hostinger shared hosting no tiene
 * Composer/SSH para instalar PHPMailer). Cubre justo lo que send_email.php
 * necesita: conectar, STARTTLS o SSL directo, AUTH LOGIN, un destinatario,
 * un mensaje multipart ya construido. No es una librería de propósito
 * general — si algún día hace falta más (varios destinatarios, reintentos,
 * colas...), esa es la señal de pasar a PHPMailer de verdad.
 *
 * No se ha podido probar contra un servidor SMTP real desde este entorno de
 * desarrollo (sin acceso de red al Hostinger real) — probar con un envío
 * real en cuanto private/mail.php tenga la contraseña puesta.
 */
final class SmtpMailer
{
    private string $host;
    private int $port;
    private string $secure; // 'tls' | 'ssl'
    private string $user;
    private string $pass;

    public function __construct(string $host, int $port, string $secure, string $user, string $pass)
    {
        $this->host = $host;
        $this->port = $port;
        $this->secure = $secure;
        $this->user = $user;
        $this->pass = $pass;
    }

    /**
     * @throws RuntimeException si cualquier paso del diálogo SMTP falla
     */
    public function send(string $fromEmail, string $fromName, string $to, string $subject, string $mimeBody, string $boundary): void
    {
        $transport = $this->secure === 'ssl' ? 'ssl://' : 'tcp://';
        $fp = @stream_socket_client("{$transport}{$this->host}:{$this->port}", $errno, $errstr, 15);
        if (!$fp) {
            throw new RuntimeException("No se pudo conectar a {$this->host}:{$this->port} — {$errstr}");
        }
        stream_set_timeout($fp, 15);

        try {
            $this->expect($fp, 220);
            $this->cmd($fp, 'EHLO lawangproperties.com', 250);

            if ($this->secure === 'tls') {
                $this->cmd($fp, 'STARTTLS', 220);
                if (!stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
                    throw new RuntimeException('No se pudo iniciar TLS (STARTTLS)');
                }
                // EHLO debe repetirse tras subir a TLS
                $this->cmd($fp, 'EHLO lawangproperties.com', 250);
            }

            $this->cmd($fp, 'AUTH LOGIN', 334);
            $this->cmd($fp, base64_encode($this->user), 334);
            $this->cmd($fp, base64_encode($this->pass), 235);

            $this->cmd($fp, "MAIL FROM:<{$fromEmail}>", 250);
            $this->cmd($fp, "RCPT TO:<{$to}>", 250);
            $this->cmd($fp, 'DATA', 354);

            $encodedSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
            $headers = "From: {$fromName} <{$fromEmail}>\r\n"
                . "To: <{$to}>\r\n"
                . "Subject: {$encodedSubject}\r\n"
                . "MIME-Version: 1.0\r\n"
                . "Content-Type: multipart/mixed; boundary=\"{$boundary}\"\r\n";

            $message = $headers . "\r\n" . $mimeBody;
            // dot-stuffing (RFC 5321): una línea que empiece por "." se escapa
            // como ".." para que el servidor no la confunda con el terminador.
            $message = preg_replace('/(\r\n|\A)\./', '$1..', $message);

            $this->cmd($fp, $message . "\r\n.", 250);
            $this->cmd($fp, 'QUIT', 221);
        } finally {
            fclose($fp);
        }
    }

    private function expect($fp, int $expectedCode): string
    {
        $resp = '';
        while (($line = fgets($fp, 515)) !== false) {
            $resp .= $line;
            // última línea de una respuesta (posiblemente) multilínea: "CODE " con espacio, no "-"
            if (isset($line[3]) && $line[3] === ' ') {
                break;
            }
        }
        $code = (int) substr($resp, 0, 3);
        if ($code !== $expectedCode) {
            throw new RuntimeException("Respuesta SMTP inesperada de {$this->host} (esperaba {$expectedCode}): " . trim($resp));
        }
        return $resp;
    }

    private function cmd($fp, string $line, int $expectedCode): string
    {
        fwrite($fp, $line . "\r\n");
        return $this->expect($fp, $expectedCode);
    }
}
