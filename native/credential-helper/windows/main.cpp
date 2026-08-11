#include <windows.h>
#include <wincred.h>

#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

namespace {

constexpr const char* kHeader = "RKCH/1";
constexpr std::size_t kMaxTargetBytes = 512;
constexpr std::size_t kMaxSecretBytes = 4096;
constexpr char kBase64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

void strip_carriage_return(std::string& value) {
    if (!value.empty() && value.back() == '\r') value.pop_back();
}

std::string base64_encode(const std::uint8_t* data, std::size_t size) {
    std::string output;
    output.reserve(((size + 2) / 3) * 4);
    for (std::size_t index = 0; index < size; index += 3) {
        const std::uint32_t a = data[index];
        const std::uint32_t b = index + 1 < size ? data[index + 1] : 0;
        const std::uint32_t c = index + 2 < size ? data[index + 2] : 0;
        const std::uint32_t value = (a << 16) | (b << 8) | c;
        output.push_back(kBase64[(value >> 18) & 0x3f]);
        output.push_back(kBase64[(value >> 12) & 0x3f]);
        output.push_back(index + 1 < size ? kBase64[(value >> 6) & 0x3f] : '=');
        output.push_back(index + 2 < size ? kBase64[value & 0x3f] : '=');
    }
    return output;
}

int base64_value(char character) {
    if (character >= 'A' && character <= 'Z') return character - 'A';
    if (character >= 'a' && character <= 'z') return character - 'a' + 26;
    if (character >= '0' && character <= '9') return character - '0' + 52;
    if (character == '+') return 62;
    if (character == '/') return 63;
    return -1;
}

bool base64_decode(const std::string& input, std::vector<std::uint8_t>& output) {
    output.clear();
    if (input.empty()) return true;
    if (input.size() % 4 != 0) return false;
    output.reserve((input.size() / 4) * 3);
    for (std::size_t index = 0; index < input.size(); index += 4) {
        int values[4] = {0, 0, 0, 0};
        int padding = 0;
        for (int offset = 0; offset < 4; ++offset) {
            const char character = input[index + offset];
            if (character == '=') {
                ++padding;
            } else {
                if (padding != 0) return false;
                values[offset] = base64_value(character);
                if (values[offset] < 0) return false;
            }
        }
        if (padding > 2 || (padding != 0 && index + 4 != input.size())) return false;
        const std::uint32_t value = (static_cast<std::uint32_t>(values[0]) << 18) |
                                    (static_cast<std::uint32_t>(values[1]) << 12) |
                                    (static_cast<std::uint32_t>(values[2]) << 6) |
                                    static_cast<std::uint32_t>(values[3]);
        output.push_back(static_cast<std::uint8_t>((value >> 16) & 0xff));
        if (padding < 2) output.push_back(static_cast<std::uint8_t>((value >> 8) & 0xff));
        if (padding < 1) output.push_back(static_cast<std::uint8_t>(value & 0xff));
    }
    return true;
}

bool utf8_to_wide(const std::string& input, std::wstring& output) {
    if (input.empty()) {
        output.clear();
        return true;
    }
    const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()), nullptr, 0);
    if (required <= 0) return false;
    output.resize(static_cast<std::size_t>(required));
    return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()), output.data(), required) == required;
}

void respond(const std::string& status, const std::string& payload = {}, const std::string& detail = {}) {
    std::cout << kHeader << '\n' << status << '\n' << payload << '\n' << detail << '\n';
    std::cout.flush();
}

void respond_windows_error(DWORD error) {
    if (error == ERROR_NOT_FOUND) respond("NOT_FOUND", "", "credential not found");
    else if (error == ERROR_ACCESS_DENIED || error == ERROR_CANCELLED) respond("DENIED", "", "credential operation denied");
    else if (error == ERROR_NO_SUCH_LOGON_SESSION) respond("UNAVAILABLE", "", "no credential-store logon session");
    else respond("UNAVAILABLE", "", "credential store error " + std::to_string(error));
}

}  // namespace

int main() {
    std::ios::sync_with_stdio(false);
    std::string header;
    std::string command;
    std::string target_base64;
    std::string secret_base64;
    if (!std::getline(std::cin, header) || !std::getline(std::cin, command) ||
        !std::getline(std::cin, target_base64) || !std::getline(std::cin, secret_base64)) {
        respond("PROTOCOL_ERROR", "", "incomplete request");
        return 2;
    }
    strip_carriage_return(header);
    strip_carriage_return(command);
    strip_carriage_return(target_base64);
    strip_carriage_return(secret_base64);
    if (header != kHeader) {
        respond("PROTOCOL_ERROR", "", "unsupported protocol");
        return 2;
    }
    if (command == "ping") {
        respond("OK", "", "windows-credential-manager");
        return 0;
    }

    std::vector<std::uint8_t> target_bytes;
    std::vector<std::uint8_t> secret_bytes;
    if (!base64_decode(target_base64, target_bytes) || !base64_decode(secret_base64, secret_bytes) ||
        target_bytes.empty() || target_bytes.size() > kMaxTargetBytes || secret_bytes.size() > kMaxSecretBytes) {
        respond("PROTOCOL_ERROR", "", "invalid field encoding or size");
        return 2;
    }
    const std::string target_utf8(target_bytes.begin(), target_bytes.end());
    std::wstring target;
    if (!utf8_to_wide("RedotKicker:" + target_utf8, target)) {
        respond("PROTOCOL_ERROR", "", "target is not valid UTF-8");
        return 2;
    }

    if (command == "store") {
        if (secret_bytes.empty() || secret_bytes.size() > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
            respond("PROTOCOL_ERROR", "", "broker session is empty or exceeds Windows credential limits");
            return 2;
        }
        CREDENTIALW credential{};
        credential.Type = CRED_TYPE_GENERIC;
        credential.TargetName = const_cast<LPWSTR>(target.c_str());
        credential.CredentialBlobSize = static_cast<DWORD>(secret_bytes.size());
        credential.CredentialBlob = secret_bytes.data();
        credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
        const BOOL stored = CredWriteW(&credential, 0);
        SecureZeroMemory(secret_bytes.data(), secret_bytes.size());
        if (!stored) {
            respond_windows_error(GetLastError());
            return 1;
        }
        respond("OK", "", "stored");
        return 0;
    }

    if (command == "read") {
        PCREDENTIALW credential = nullptr;
        if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
            respond_windows_error(GetLastError());
            return 1;
        }
        if (credential->CredentialBlobSize > kMaxSecretBytes) {
            SecureZeroMemory(credential->CredentialBlob, credential->CredentialBlobSize);
            CredFree(credential);
            respond("PROTOCOL_ERROR", "", "stored broker session exceeds protocol limit");
            return 2;
        }
        const std::string encoded = base64_encode(credential->CredentialBlob, credential->CredentialBlobSize);
        SecureZeroMemory(credential->CredentialBlob, credential->CredentialBlobSize);
        CredFree(credential);
        respond("OK", encoded, "read");
        return 0;
    }

    if (command == "delete") {
        if (!CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0)) {
            const DWORD error = GetLastError();
            if (error == ERROR_NOT_FOUND) {
                respond("NOT_FOUND", "", "credential not found");
                return 0;
            }
            respond_windows_error(error);
            return 1;
        }
        respond("OK", "", "deleted");
        return 0;
    }

    respond("PROTOCOL_ERROR", "", "unknown command");
    return 2;
}
