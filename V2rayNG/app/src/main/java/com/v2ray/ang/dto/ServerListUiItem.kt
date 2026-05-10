package com.v2ray.ang.dto

sealed interface ServerListUiItem {
    data class GroupHeader(
        val subscriptionId: String,
        val title: String,
        val isExpanded: Boolean,
    ) : ServerListUiItem

    data class Server(
        val cache: ServersCache,
        val serverIndex: Int,
    ) : ServerListUiItem

    data object Footer : ServerListUiItem
}
