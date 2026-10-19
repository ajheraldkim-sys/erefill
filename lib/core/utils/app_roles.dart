abstract final class AppRoles {
  static bool isDesktopAdmin(String? role) {
    switch (role?.trim().toLowerCase()) {
      case 'admin':
      case 'super_admin':
      case 'administrator':
        return true;
      default:
        return false;
    }
  }
}
